param([ValidateSet('Inspect','Rows','Compare','Detail','BankPlan')][string]$Mode='Inspect',[string]$Table,[long]$SourceRecId=0,[long]$TargetRecId=0)
$ErrorActionPreference='Stop'
try {
 $user=[Console]::ReadLine();$plain=[Console]::ReadLine()
 if([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrEmpty($plain)){throw 'SQL girisi eksik.'}
 $secure=ConvertTo-SecureString $plain -AsPlainText -Force;$plain=$null
 $credential=[pscredential]::new($user,$secure)
 if($Mode -eq 'Inspect'){& (Join-Path $PSScriptRoot 'Inspect-Sentez.ps1') -Authentication Sql -Credential $credential;exit 0}
 $tokens=$null;$errors=$null
 $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Inspect-Sentez.ps1'),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw 'Inceleme modulu yuklenemedi.'}
 foreach($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)){Invoke-Expression $f.Extent.Text}
 $Authentication='Sql';$Credential=$credential
 $profile=Get-Content (Join-Path $PSScriptRoot 'profile.json') -Raw|ConvertFrom-Json
 if($Mode -eq 'BankPlan'){
  . (Join-Path $PSScriptRoot 'Bank-Read.ps1')
  Write-BankSnapshot $profile
  exit 0
 }
 if($Table -cnotmatch '^dbo\.Erp_[A-Za-z0-9_]+$'){throw ("Tablo adi desteklenmiyor: ["+$Table+"]")}
 $latest=Get-ChildItem (Join-Path $PSScriptRoot 'reports') -Filter inspection.json -Recurse|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
 if(!$latest){throw 'Once karsilastirma yapin.'}
 $report=Get-Content $latest.FullName -Raw|ConvertFrom-Json
 $approved=@($report.Tables|Where-Object {$_.Table -eq $Table -and $_.Status -eq 'CompanyScopedCandidate'})
 if($approved.Count -ne 1){throw 'Tablo sirket kapsaminda dogrulanmadi.'}
 $keyColumn=switch($Table){'dbo.Erp_CurrentAccount'{'CurrentAccountCode'} 'dbo.Erp_Inventory'{'InventoryCode'} default{$null}}
 if($Mode -in @('Compare','Detail') -and !$keyColumn){throw 'Kayit eslestirme bu surumde cari ve stok kartlarinda destekleniyor.'}
 $result=[ordered]@{}
 if($Mode -eq 'Compare'){
  $route=@($profile.source.server,$profile.source.database,[string]$profile.source.companyRecId,$profile.target.server,$profile.target.database,[string]$profile.target.companyRecId)|ConvertTo-Json -Compress
  $result.Table=$Table;$result.KeyColumn=$keyColumn;$result.Route=$route;$result.GeneratedAt=(Get-Date).ToString('o')
 }
 foreach($side in @('Source','Target')){
  $endpoint=if($side -eq 'Source'){$profile.source}else{$profile.target}
  $connection=Open-Database $endpoint
  try{
   $null=Get-Company $connection $endpoint
   $parts=$Table.Split('.');$name=(Quote-Name $parts[0])+'.'+(Quote-Name $parts[1])
   if($Mode -eq 'Compare'){
    $schemaFile=Join-Path $latest.DirectoryName ($side.ToLower()+'-schema.csv')
    $excluded=@('RecId','CompanyId','InsertedAt','InsertedBy','UpdatedAt','UpdatedBy')
    $columns=@(Import-Csv $schemaFile|Where-Object {$_.TableName -eq $parts[1] -and $_.SchemaName -eq $parts[0] -and $_.ColumnName -notin $excluded -and $_.is_computed -eq 'False' -and $_.TypeName -notin @('timestamp','rowversion')})
    if($columns.Count -eq 0){throw 'Karsilastirma kolonlari bulunamadi.'}
    $columnList=($columns|ForEach-Object {'t.'+(Quote-Name $_.ColumnName)}) -join ','
    $key=Quote-Name $keyColumn
    $query="SELECT t.RecId, CONVERT(nvarchar(400),t.$key) AS MatchKey, CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONVERT(nvarchar(max),(SELECT $columnList FOR XML RAW('r'),ELEMENTS XSINIL,BINARY BASE64,TYPE)))),2) AS Fingerprint FROM $name t WHERE t.CompanyId=@companyId ORDER BY t.RecId"
    $data=Read-Table $connection $query $endpoint.companyRecId
    $result[$side]=@($data.Rows|ForEach-Object {[pscustomobject]@{RecId=[long]$_.RecId;MatchKey=if($_.MatchKey -is [DBNull]){$null}else{[string]$_.MatchKey};Fingerprint=[string]$_.Fingerprint}})
   }else{
    $query="SELECT TOP (200) * FROM $name WHERE CompanyId=@companyId ORDER BY RecId"
    if($Mode -eq 'Detail'){$rec=if($side -eq 'Source'){$SourceRecId}else{$TargetRecId};$query="SELECT * FROM $name WHERE CompanyId=@companyId AND RecId=$([long]$rec)"}
    $data=Read-Table $connection $query $endpoint.companyRecId
    $result[$side]=@($data.Rows|ForEach-Object {$r=[ordered]@{};foreach($col in $data.Columns){$v=$_[$col.ColumnName];$r[$col.ColumnName]=if($v -is [DBNull]){$null}elseif($v -is [byte[]]){[Convert]::ToBase64String($v)}elseif($v -is [DateTime]){$v.ToString('o',[Globalization.CultureInfo]::InvariantCulture)}elseif($v -is [System.IFormattable]){$v.ToString($null,[Globalization.CultureInfo]::InvariantCulture)}else{[string]$v}};[pscustomobject]$r})
   }
  }finally{$connection.Dispose()}
 }
 $file=if($Mode -eq 'Compare'){'comparison-snapshot.json'}elseif($Mode -eq 'Detail'){'record-detail.json'}else{'row-preview.json'}
 $result|ConvertTo-Json -Depth 8|Set-Content (Join-Path $PSScriptRoot $file) -Encoding UTF8
}catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}
finally{$credential=$null;$secure=$null;$plain=$null}


