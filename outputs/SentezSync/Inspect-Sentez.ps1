[CmdletBinding()]
param(
    [string]$ProfilePath = (Join-Path $PSScriptRoot 'profile.json'),
    [ValidateSet('Windows','Sql')][string]$Authentication = 'Windows',
    [System.Management.Automation.PSCredential]$Credential,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'reports'),
    [switch]$SkipCounts
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Data
$profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
if ($profile.source.database -eq $profile.target.database -and $profile.source.server -eq $profile.target.server) {
    throw 'Kaynak ve hedef ayni veritabani olamaz.'
}
if ($Authentication -eq 'Sql' -and !$Credential) {
    $Credential = Get-Credential -Message 'Test SQL Server hesabi. Parola dosyaya kaydedilmez.'
    if (!$Credential) { throw 'SQL girisi iptal edildi.' }
}
function Open-Database($endpoint) {
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = [string]$endpoint.server
    $builder['Initial Catalog'] = [string]$endpoint.database
    $builder['Connect Timeout'] = 8
    $builder['Application Name'] = 'SentezSync ReadOnly Inspection'
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Persist Security Info'] = $false
    if ($Authentication -eq 'Windows') { $builder['Integrated Security'] = $true }
    $connection = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
    if ($Authentication -eq 'Sql') {
        $secret = $Credential.Password.Copy()
        $secret.MakeReadOnly()
        $connection.Credential = New-Object System.Data.SqlClient.SqlCredential($Credential.UserName, $secret)
    }
    try { $connection.Open(); return $connection }
    catch { $connection.Dispose(); throw }
}
function Read-Table($connection, [string]$sql, $companyId) {
    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $command.CommandTimeout = 60
    if ($null -ne $companyId) {
        $parameter = $command.Parameters.Add('@companyId', [System.Data.SqlDbType]::Int)
        $parameter.Value = [int]$companyId
    }
    try {
        $table = New-Object System.Data.DataTable
        $reader = $command.ExecuteReader()
        try { $table.Load($reader) } finally { $reader.Dispose() }
        return ,$table
    } finally { $command.Dispose() }
}
function Quote-Name([string]$name) { return '[' + $name.Replace(']', ']]') + ']' }
function Get-Company($connection, $endpoint) {
    $table = Read-Table $connection 'SELECT RecId,CompanyCode,CompanyName FROM dbo.Erp_Company WHERE RecId=@companyId' $endpoint.companyRecId
    if ($table.Rows.Count -ne 1) { throw "Sirket bulunamadi: $($endpoint.database) / $($endpoint.companyRecId)" }
    $row = $table.Rows[0]
    if ($endpoint.companyCode -and [string]$row.CompanyCode -ne [string]$endpoint.companyCode) {
        throw "Sirket kodu profil ile uyusmuyor: $($endpoint.database)"
    }
    return [pscustomobject]@{ Database=$endpoint.database; RecId=[int]$row.RecId; Code=[string]$row.CompanyCode; Name=[string]$row.CompanyName }
}
$schemaSql = @'
SELECT s.name AS SchemaName,t.name AS TableName,c.name AS ColumnName,
       ty.name AS TypeName,c.max_length,c.precision,c.scale,c.is_nullable,c.is_identity,c.is_computed,
       CASE WHEN EXISTS(SELECT 1 FROM sys.columns x WHERE x.object_id=t.object_id AND x.name='CompanyId') THEN 1 ELSE 0 END AS HasCompanyId
FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id
JOIN sys.columns c ON c.object_id=t.object_id
JOIN sys.types ty ON ty.user_type_id=c.user_type_id
WHERE t.is_ms_shipped=0 ORDER BY s.name,t.name,c.column_id
'@
$foreignKeySql = @'
SELECT ps.name AS ChildSchema,pt.name AS ChildTable,pc.name AS ChildColumn,
       rs.name AS ParentSchema,rt.name AS ParentTable,rc.name AS ParentColumn,
       fk.name AS ConstraintName,fk.delete_referential_action_desc AS DeleteAction
FROM sys.foreign_key_columns fc JOIN sys.foreign_keys fk ON fk.object_id=fc.constraint_object_id
JOIN sys.tables pt ON pt.object_id=fc.parent_object_id JOIN sys.schemas ps ON ps.schema_id=pt.schema_id
JOIN sys.columns pc ON pc.object_id=pt.object_id AND pc.column_id=fc.parent_column_id
JOIN sys.tables rt ON rt.object_id=fc.referenced_object_id JOIN sys.schemas rs ON rs.schema_id=rt.schema_id
JOIN sys.columns rc ON rc.object_id=rt.object_id AND rc.column_id=fc.referenced_column_id
'@
function Group-Schema($table) {
    $map = @{}
    foreach ($row in $table.Rows) {
        $key = [string]$row.SchemaName + '.' + [string]$row.TableName
        if (!$map.ContainsKey($key)) { $map[$key] = @() }
        $map[$key] += $row
    }
    return $map
}
function Schema-Signature($rows) {
    return (($rows | ForEach-Object {
        '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $_.ColumnName,$_.TypeName,$_.max_length,$_.precision,$_.scale,$_.is_nullable,$_.is_identity,$_.is_computed
    }) -join ';')
}
$sourceConnection = $null
$targetConnection = $null
try {
    Write-Host 'Kaynak ve hedef baglantilari kontrol ediliyor...'
    $sourceConnection = Open-Database $profile.source
    $targetConnection = Open-Database $profile.target
    $sourceCompany = Get-Company $sourceConnection $profile.source
    $targetCompany = Get-Company $targetConnection $profile.target
    $sourceSchema = Read-Table $sourceConnection $schemaSql $null
    $targetSchema = Read-Table $targetConnection $schemaSql $null
    $sourceMap = Group-Schema $sourceSchema
    $targetMap = Group-Schema $targetSchema
    $results = @()
    foreach ($key in ($sourceMap.Keys | Sort-Object)) {
        $rows = $sourceMap[$key]
        $first = $rows[0]
        $status = 'ReviewRequired'
        $sameSchema = $false
        if (!$targetMap.ContainsKey($key)) { $status = 'MissingTargetTable' }
        else {
            $sameSchema = (Schema-Signature $rows) -ceq (Schema-Signature $targetMap[$key])
            if (!$sameSchema) { $status = 'SchemaMismatch' }
            elseif ([string]$first.TableName -notlike 'Erp_*') { $status = 'SystemOrNonErpReview' }
            elseif (!$first.HasCompanyId) { $status = 'OwnershipReview' }
            else { $status = 'CompanyScopedCandidate' }
        }
        $sourceCount = $null; $targetCount = $null; $countError = $null
        if (!$SkipCounts -and $status -eq 'CompanyScopedCandidate') {
            $name = (Quote-Name $first.SchemaName) + '.' + (Quote-Name $first.TableName)
            try {
                $sc = Read-Table $sourceConnection "SELECT COUNT_BIG(*) AS N FROM $name WHERE CompanyId=@companyId" $profile.source.companyRecId
                $tc = Read-Table $targetConnection "SELECT COUNT_BIG(*) AS N FROM $name WHERE CompanyId=@companyId" $profile.target.companyRecId
                $sourceCount = [long]$sc.Rows[0].N; $targetCount = [long]$tc.Rows[0].N
            } catch { $countError = $_.Exception.GetBaseException().Message; $status = 'CountFailed' }
        }
        $results += [pscustomobject]@{
            Table=$key; Status=$status; SchemaMatches=$sameSchema
            HasCompanyId=[bool]$first.HasCompanyId
            HasUniqueId=(@($rows | Where-Object ColumnName -eq 'UniqueId').Count -gt 0)
            SourceCount=$sourceCount; TargetCount=$targetCount; Error=$countError
        }
    }
    $sourceFks = Read-Table $sourceConnection $foreignKeySql $null
    $targetFks = Read-Table $targetConnection $foreignKeySql $null
    $runPath = Join-Path $OutputDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    $results | Export-Csv (Join-Path $runPath 'tables.csv') -NoTypeInformation -Encoding UTF8
    $sourceSchema | Export-Csv (Join-Path $runPath 'source-schema.csv') -NoTypeInformation -Encoding UTF8
    $targetSchema | Export-Csv (Join-Path $runPath 'target-schema.csv') -NoTypeInformation -Encoding UTF8
    $sourceFks | Export-Csv (Join-Path $runPath 'source-relations.csv') -NoTypeInformation -Encoding UTF8
    $targetFks | Export-Csv (Join-Path $runPath 'target-relations.csv') -NoTypeInformation -Encoding UTF8
    [pscustomobject]@{
        GeneratedAt=(Get-Date).ToString('o'); Source=$sourceCompany; Target=$targetCompany
        Mode='ReadOnly'; ReplicationEnabled=$false; DeletesRequested=[bool]$profile.replicateDeletes
        Tables=$results; TargetOnlyTables=@($targetMap.Keys | Where-Object { !$sourceMap.ContainsKey($_) })
        Limitations=@('Counts are not a consistent snapshot and do not establish data equality.',
        'Child tables without CompanyId and logical relations without foreign keys need ownership review.',
        'UniqueId presence does not establish uniqueness or a valid match.',
        'No data was inserted, updated or deleted. This is not a replication engine.')
    } | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $runPath 'inspection.json') -Encoding UTF8
    Write-Host "Inceleme tamamlandi: $runPath"
    Write-Host 'Aktarim yapilmadi. Esit satir sayisi, verilerin esit oldugunu gostermez.'
} finally {
    if ($sourceConnection) { $sourceConnection.Dispose() }
    if ($targetConnection) { $targetConnection.Dispose() }
}
