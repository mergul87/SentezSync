function Write-BankSnapshot($profile) {
 if($profile.source.server -eq $profile.target.server -and $profile.source.database -eq $profile.target.database){throw 'Kaynak ve hedef ayni olamaz.'}
 $result=[ordered]@{Route=(@($profile.source.server,$profile.source.database,[string]$profile.source.companyRecId,$profile.target.server,$profile.target.database,[string]$profile.target.companyRecId)|ConvertTo-Json -Compress);StartedAt=(Get-Date).ToString('o')}
 foreach($side in @('Source','Target')){
  $endpoint=if($side -eq 'Source'){$profile.source}else{$profile.target}
  $connection=Open-Database $endpoint
  try{
   $null=Get-Company $connection $endpoint
   $schema=Read-Table $connection "SELECT t.name TableName,c.name ColumnName,c.column_id FROM sys.tables t JOIN sys.columns c ON c.object_id=t.object_id WHERE SCHEMA_NAME(t.schema_id)='dbo' AND t.name IN ('Erp_BankReceipt','Erp_BankReceiptItem','Erp_BankReceiptAttachment') AND c.is_computed=0 AND c.system_type_id<>189 ORDER BY t.name,c.column_id" $null
   $lists=@{}
   foreach($tableName in @('Erp_BankReceipt','Erp_BankReceiptItem','Erp_BankReceiptAttachment')){
    $cols=@($schema.Rows|Where-Object {$_.TableName -eq $tableName -and $_.ColumnName -notin @('RecId','CompanyId','BankReceiptId','InsertedAt','InsertedBy','UpdatedAt','UpdatedBy')})
    if(!$cols.Count){throw "Banka tablosu bulunamadi: $tableName"}
    $alias=if($tableName -eq 'Erp_BankReceipt'){'h'}elseif($tableName -eq 'Erp_BankReceiptItem'){'i'}else{'a'}
    $lists[$tableName]=($cols|ForEach-Object {$alias+'.'+(Quote-Name $_.ColumnName)}) -join ','
   }
   $header=$lists.Erp_BankReceipt;$items=$lists.Erp_BankReceiptItem;$attachments=$lists.Erp_BankReceiptAttachment
   $sql=@"
SELECT TOP (1000) h.RecId,CONVERT(varchar(36),h.UniqueId) UniqueId,h.ReceiptType,h.ReceiptNo,h.ReceiptDate,
 h.InsertedBy,u.UserCode Creator,h.UpdatedBy,uu.UserCode Updater,h.GLReceiptId,h.SourceId,h.SourceModule,
 CONVERT(int,ISNULL(h.IsDeleted,0)) IsDeleted,
 (SELECT COUNT(*) FROM dbo.Erp_BankReceiptItem i WHERE i.BankReceiptId=h.RecId) ItemCount,
 (SELECT COUNT(*) FROM dbo.Erp_BankReceiptAttachment a WHERE a.BankReceiptId=h.RecId) AttachmentCount,
 (SELECT COUNT(*) FROM dbo.Erp_BankReceiptItem i LEFT JOIN dbo.Erp_BankAccount b ON b.RecId=i.BankAccountId LEFT JOIN dbo.Erp_Bank bank ON bank.RecId=b.BankId WHERE i.BankReceiptId=h.RecId AND i.BankAccountId IS NOT NULL AND (b.RecId IS NULL OR bank.RecId IS NULL OR bank.CompanyId<>@companyId)) InvalidBankReferences,
 CASE WHEN h.GLReceiptId IS NOT NULL AND NOT EXISTS(SELECT 1 FROM dbo.Erp_GLReceipt g WHERE g.RecId=h.GLReceiptId AND g.CompanyId=@companyId) THEN 1 ELSE 0 END InvalidGLReference,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONVERT(nvarchar(max),(SELECT $header FOR XML RAW('h'),ELEMENTS XSINIL,BINARY BASE64,TYPE)))),2) HeaderHash,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONVERT(nvarchar(max),(SELECT $items FROM dbo.Erp_BankReceiptItem i WHERE i.BankReceiptId=h.RecId ORDER BY i.ItemOrderNo,i.RecId FOR XML RAW('i'),ELEMENTS XSINIL,BINARY BASE64,TYPE)))),2) ItemsHash,
 CONVERT(varchar(64),HASHBYTES('SHA2_256',CONVERT(varbinary(max),CONVERT(nvarchar(max),(SELECT $attachments FROM dbo.Erp_BankReceiptAttachment a WHERE a.BankReceiptId=h.RecId ORDER BY a.RecId FOR XML RAW('a'),ELEMENTS XSINIL,BINARY BASE64,TYPE)))),2) AttachmentsHash
FROM dbo.Erp_BankReceipt h LEFT JOIN dbo.Meta_User u ON u.RecId=h.InsertedBy LEFT JOIN dbo.Meta_User uu ON uu.RecId=h.UpdatedBy
WHERE h.CompanyId=@companyId AND h.RecId>__AFTER_ID__ ORDER BY h.RecId
"@
   $all=New-Object 'System.Collections.Generic.List[object]'
   $after=0L
   do {
   $data=Read-Table $connection ($sql.Replace('__AFTER_ID__',[string]$after)) $endpoint.companyRecId
   $batch=@($data.Rows|ForEach-Object {
    $row=[ordered]@{}
    foreach($c in $data.Columns){$v=$_[$c.ColumnName];$row[$c.ColumnName]=if($v -is [DBNull]){$null}elseif($v -is [DateTime]){$v.ToString('o')}else{$v}}
    [pscustomobject]$row
   })
   foreach($row in $batch){$all.Add($row)}
   if($batch.Count){$after=[long]$batch[-1].RecId}
   } while($batch.Count -eq 1000)
   $result[$side]=$all.ToArray()
  }finally{$connection.Dispose()}
 }
 $result.GeneratedAt=(Get-Date).ToString('o')
 $path=Join-Path $PSScriptRoot 'bank-snapshot.json';$temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{$result|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $temp -Encoding UTF8;if(Test-Path $path){[IO.File]::Replace($temp,$path,$null)}else{[IO.File]::Move($temp,$path)}}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp}}
}

