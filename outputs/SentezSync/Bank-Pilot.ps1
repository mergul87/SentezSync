[CmdletBinding()]
param([Parameter(Mandatory=$true)][long]$SourceRecId,[switch]$Execute)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Bank-Transfer.ps1')
if($SourceRecId -le 0){throw 'Kaynak RecId gerekli.'}
$profile=Get-Content (Join-Path $PSScriptRoot 'profile.json') -Raw|ConvertFrom-Json
if($profile.source.server -ne '192.168.3.48' -or $profile.target.server -ne '192.168.3.48' -or $profile.source.database -ne 'SentezLiveDev2025' -or $profile.target.database -ne 'SentezLiveDev2024' -or $profile.source.companyRecId -ne 7 -or $profile.target.companyRecId -ne 7){throw 'Bu pilot yalniz dogrulanmis test rotasini destekler.'}
$user=[Console]::ReadLine();$secret=[Console]::ReadLine()
if(!$user -or !$secret){throw 'Sentez API kullanicisi ve parolasi gerekli.'}
$base='http://192.168.3.48:5151';$headers=$null;$lock=$null
function Invoke-PilotApi([string]$path,$body){
 try{
  if($null -ne $body){$r=Invoke-RestMethod -Uri ($base+$path) -Headers $headers -Method Post -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes(($body|ConvertTo-Json -Depth 50 -Compress))) -TimeoutSec 60}
  else{$r=Invoke-RestMethod -Uri ($base+$path) -Headers $headers -TimeoutSec 60}
 }catch{throw "API baglantisi tamamlanamadi: $path. Yazma istegiyse sonuc belirsiz; otomatik tekrar yapilmaz."}
 if(!$r.IsOk){throw ('Sentez API reddetti: '+$r.ErrorMessage+' '+($r.ServerMessages -join ' '))}
 return $r
}
try{
 $uri=$base+'/api/Authentication/Login?userCode='+[uri]::EscapeDataString($user)+'&password='+[uri]::EscapeDataString($secret)+'&companyCode=012018&userType=0'
 try{$login=Invoke-RestMethod -Uri $uri -Method Post -TimeoutSec 30}catch{throw 'API girisi tamamlanamadi.'}
 if(!$login.IsOk){throw 'API girisi reddedildi.'}
 $data=$login.Data;if($data -is [string]){try{$data=$data|ConvertFrom-Json}catch{}}
 $token=if($data -is [string]){$data}else{@($data.PSObject.Properties|Where-Object {$_.Name -in @('Token','Session','SessionId')}|Select-Object -First 1).Value}
 if(!$token){throw 'API oturumu alinamadi.'}
 $headers=@{Authorization=('Bearer '+$token)};$secret=$null;$uri=$null;$login=$null;$data=$null;$token=$null
 $directory=Join-Path $PSScriptRoot 'transfers';$null=New-Item -ItemType Directory -Path $directory -Force
 $journal=Join-Path $directory ("bank-$SourceRecId.json")
 if($Execute){$lock=[IO.File]::Open((Join-Path $directory 'bank-transfer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);if(Test-Path $journal){throw 'Bu fis icin aktarim durumu zaten var; once uzlastirma gerekli.'}}
 $bank="SELECT GLReceiptId FROM SentezLiveDev2025.dbo.Erp_BankReceipt WHERE RecId=$SourceRecId AND CompanyId=7"
 $query=@"
SELECT (SELECT * FROM SentezLiveDev2025.dbo.Erp_BankReceipt WHERE RecId=$SourceRecId AND CompanyId=7 FOR JSON PATH,INCLUDE_NULL_VALUES) BankHeader,
(SELECT i.* FROM SentezLiveDev2025.dbo.Erp_BankReceiptItem i JOIN SentezLiveDev2025.dbo.Erp_BankReceipt b ON b.RecId=i.BankReceiptId WHERE b.RecId=$SourceRecId AND b.CompanyId=7 ORDER BY i.RecId FOR JSON PATH,INCLUDE_NULL_VALUES) BankItems,
(SELECT i.* FROM SentezLiveDev2025.dbo.Erp_BankReceiptAttachment i JOIN SentezLiveDev2025.dbo.Erp_BankReceipt b ON b.RecId=i.BankReceiptId WHERE b.RecId=$SourceRecId AND b.CompanyId=7 ORDER BY i.RecId FOR JSON PATH,INCLUDE_NULL_VALUES) BankAttachments,
(SELECT * FROM SentezLiveDev2025.dbo.Erp_GLReceipt WHERE RecId=($bank) AND CompanyId=7 FOR JSON PATH,INCLUDE_NULL_VALUES) GLHeader,
(SELECT i.* FROM SentezLiveDev2025.dbo.Erp_GLReceiptItem i JOIN SentezLiveDev2025.dbo.Erp_GLReceipt g ON g.RecId=i.GLReceiptId WHERE g.RecId=($bank) AND g.CompanyId=7 ORDER BY i.RecId FOR JSON PATH,INCLUDE_NULL_VALUES) GLItems,
(SELECT x.* FROM SentezLiveDev2025.dbo.Erp_GLReceiptItemInv x JOIN SentezLiveDev2025.dbo.Erp_GLReceiptItem i ON i.RecId=x.GLReceiptItemId WHERE i.GLReceiptId=($bank) ORDER BY x.RecId FOR JSON PATH,INCLUDE_NULL_VALUES) GLInvoices,
(SELECT * FROM SentezLiveDev2025.dbo.Erp_CostCenterDistribution WHERE GLReceiptId=($bank) ORDER BY RecId FOR JSON PATH,INCLUDE_NULL_VALUES) GLCosts
"@
 $source=Invoke-PilotApi '/api/Utility/UtilityQuery' @{query=$query}
 if(@($source.Data).Count -ne 1){throw 'Kaynak paket alinamadi.'};$raw=$source.Data[0]
 $ids=@{GLAccount=New-Object 'System.Collections.Generic.HashSet[long]';BankAccount=New-Object 'System.Collections.Generic.HashSet[long]';Forex=New-Object 'System.Collections.Generic.HashSet[long]'}
 foreach($table in @('BankHeader','BankItems','GLHeader','GLItems')){
  if(!$raw.$table){continue}
  $parsed=ConvertFrom-Json -InputObject $raw.$table
  foreach($row in $parsed){
   foreach($property in $row.PSObject.Properties){
    if($null -eq $property.Value){continue}
    $kind=switch($property.Name){'BankAccountId'{'BankAccount'} 'GLAccountId'{'GLAccount'} 'AccountId'{'GLAccount'} 'ForexId'{'Forex'} 'TransactionForexId'{'Forex'} 'LedgerForexId'{'Forex'} default{$null}}
    if($kind){$null=$ids[$kind].Add([long]$property.Value)}
   }
  }
 }
 $queries=New-Object 'System.Collections.Generic.List[string]'
 foreach($kind in @('GLAccount','BankAccount','Forex')){
  if(!$ids[$kind].Count){continue};$list=($ids[$kind]|Sort-Object) -join ','
  switch($kind){
   'GLAccount' {$queries.Add("SELECT 'GLAccount' Kind,s.RecId SourceId,t.RecId TargetId,s.AccountCode Code,s.CompanyId SourceCompany,t.CompanyId TargetCompany FROM SentezLiveDev2025.dbo.Erp_GLAccount s LEFT JOIN SentezLiveDev2024.dbo.Erp_GLAccount t ON t.CompanyId=7 AND t.AccountCode=s.AccountCode WHERE s.CompanyId=7 AND s.RecId IN ($list)")}
   'BankAccount' {$queries.Add("SELECT 'BankAccount' Kind,s.RecId SourceId,t.RecId TargetId,b.BankCode+':'+s.AccountCode Code,b.CompanyId SourceCompany,tb.CompanyId TargetCompany FROM SentezLiveDev2025.dbo.Erp_BankAccount s JOIN SentezLiveDev2025.dbo.Erp_Bank b ON b.RecId=s.BankId LEFT JOIN SentezLiveDev2024.dbo.Erp_Bank tb ON tb.CompanyId=7 AND tb.BankCode=b.BankCode LEFT JOIN SentezLiveDev2024.dbo.Erp_BankAccount t ON t.BankId=tb.RecId AND t.AccountCode=s.AccountCode WHERE b.CompanyId=7 AND s.RecId IN ($list)")}
   'Forex' {$queries.Add("SELECT 'Forex' Kind,s.RecId SourceId,t.RecId TargetId,s.ForexCode Code,NULL SourceCompany,NULL TargetCompany FROM SentezLiveDev2025.dbo.Meta_Forex s LEFT JOIN SentezLiveDev2024.dbo.Meta_Forex t ON t.ForexCode=s.ForexCode WHERE s.RecId IN ($list)")}
  }
 }
 if(!$queries.Count){throw 'Referans listesi bos.'}
 $mapping=Invoke-PilotApi '/api/Utility/UtilityQuery' @{query=($queries -join ' UNION ALL ')}
 $pair=Convert-BankPair $raw @($mapping.Data)
 $b=New-BankPayload $pair;$null=New-GLPayload $pair 1
 $plan=[ordered]@{SourceBankId=$pair.BankId;SourceGLId=$pair.GLId;ReceiptNo=$pair.ReceiptNo;UniqueId=$pair.UniqueId;BankItemCount=$pair.Tables.BankItems.Count;GLItemCount=$pair.Tables.GLItems.Count;Debit=$pair.Tables.GLHeader[0].Debit;Credit=$pair.Tables.GLHeader[0].Credit;References=@($mapping.Data);GeneratedAt=(Get-Date).ToString('o');WritesPerformed=$false}
 Save-TransferState (Join-Path $directory ("bank-$SourceRecId-plan.json")) $plan
 Save-TransferState (Join-Path $directory ("bank-$SourceRecId-source.json")) $raw
 if(!$Execute){$plan|ConvertTo-Json -Depth 10;return}
 # Repeat the source read immediately before writing; changed packages are rejected.
 $fresh=Invoke-PilotApi '/api/Utility/UtilityQuery' @{query=$query}
 if(($raw|ConvertTo-Json -Depth 20 -Compress) -cne ($fresh.Data[0]|ConvertTo-Json -Depth 20 -Compress)){throw 'Kaynak paket hazirlama sirasinda degisti; aktarim yapilmadi.'}
 $result=Invoke-BankPairTransfer $pair {param($path,$body) Invoke-PilotApi $path $body} $journal
 $result|ConvertTo-Json -Depth 15
}finally{if($lock){$lock.Dispose()};$secret=$null;$headers=$null;$token=$null;$uri=$null}
