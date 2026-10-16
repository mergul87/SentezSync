# Banka/muhasebe paketinin API yazma adaptoru. Bu dosya tek basina calistirilmaz.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Convert-BankPair($raw,$references) {
 $tables=[ordered]@{}
 foreach($name in @('BankHeader','BankItems','BankAttachments','GLHeader','GLItems','GLInvoices','GLCosts')){
  $tables[$name]=@()
  if(![string]::IsNullOrWhiteSpace([string]$raw.$name)){$parsed=ConvertFrom-Json -InputObject $raw.$name;$tables[$name]=@($parsed)}
 }
 if($tables.BankHeader.Count -ne 1 -or $tables.GLHeader.Count -ne 1){throw 'Tek banka ve tek muhasebe basligi gerekli.'}
 $b=$tables.BankHeader[0];$g=$tables.GLHeader[0]
 if($b.CompanyId -ne 7 -or $g.CompanyId -ne 7){throw 'Sirket kapsami hatali.'}
 if($b.GLReceiptId -ne $g.RecId -or $g.SourceModule -ne 15 -or $g.SourceId -ne $b.RecId){throw 'Banka muhasebe baglantisi dogrulanamadi.'}
 if(!$tables.BankItems.Count -or !$tables.GLItems.Count){throw 'Satirsiz fis aktarilamaz.'}
 if($tables.GLInvoices.Count -or $tables.GLCosts.Count){throw 'Muhasebe fatura/masraf dagitim adaptoru henuz desteklenmiyor.'}
 if(!$b.UniqueId -or [guid]$b.UniqueId -eq [guid]::Empty){throw 'Yeni banka fisi icin UniqueId gerekli.'}
 foreach($row in @($tables.BankHeader)+@($tables.BankItems)+@($tables.GLHeader)+@($tables.GLItems)){
  foreach($name in @('IsDeleted','IsCancelled','IsLocked','IsClosed')){
   if($row.PSObject.Properties[$name] -and $row.$name -and [int]$row.$name -ne 0){throw "Silinmis/iptal/kilitli/kapali fis aktarilamaz: $name"}
  }
 }
 foreach($row in $tables.BankItems){if($row.BankReceiptId -ne $b.RecId){throw 'Banka satir sahipligi hatali.'}}
 foreach($row in $tables.BankAttachments){if($row.BankReceiptId -ne $b.RecId){throw 'Ek sahipligi hatali.'}}
 foreach($row in $tables.GLItems){if($row.GLReceiptId -ne $g.RecId){throw 'Muhasebe satir sahipligi hatali.'}}
 $debit=[decimal]0;$credit=[decimal]0
 foreach($row in $tables.GLItems){$debit+=[decimal]$row.Debit;$credit+=[decimal]$row.Credit}
 if($debit -ne $credit -or $debit -ne [decimal]$g.Debit -or $credit -ne [decimal]$g.Credit){throw 'Muhasebe fisi dengeli degil veya toplamlar uyusmuyor.'}
 $maps=@{}
 foreach($r in $references){
  $key=[string]$r.Kind+':'+[string]$r.SourceId
  if(!$r.TargetId -or $maps.ContainsKey($key)){throw "Eksik veya coklu referans: $key"}
  if($r.Kind -ne 'Forex' -and ($r.SourceCompany -ne 7 -or $r.TargetCompany -ne 7)){throw 'Referans baska sirkete ait.'}
  $maps[$key]=[long]$r.TargetId
 }
 return [pscustomobject]@{Tables=$tables;Maps=$maps;BankId=[long]$b.RecId;GLId=[long]$g.RecId;UniqueId=[string]$b.UniqueId;ReceiptNo=[string]$b.ReceiptNo;ReceiptType=[int]$b.ReceiptType;GLReceiptNo=[string]$g.ReceiptNo;GLReceiptType=[int]$g.ReceiptType;GLReceiptDate=[string]$g.ReceiptDate}
}
function Convert-TransferRow($row,$pair,[string]$kind,[long]$targetBankId=0) {
 $result=[ordered]@{}
 $skip=@('InsertedAt','InsertedBy','UpdatedAt','UpdatedBy','DeletedAt','DeletedBy')
 foreach($p in $row.PSObject.Properties){
  $name=$p.Name;$value=$p.Value
  if($name -in $skip -or $null -eq $value){continue}
  if($name -eq 'RecId'){$result[$name]=-[long]$value;continue}
  if($name -eq 'CompanyId'){$result[$name]=7;continue}
  if($name -eq 'UniqueId'){$result[$name]=$value;continue}
  if($name -eq 'GLReceiptId' -and $kind -eq 'Bank'){continue}
  if($name -eq 'BankReceiptId'){$result[$name]=-$pair.BankId;continue}
  if($name -eq 'GLReceiptId' -and $kind -eq 'GL'){$result[$name]=-$pair.GLId;continue}
  if($name -eq 'SourceId' -and $kind -eq 'GL'){
   if([long]$value -ne $pair.BankId -or $row.SourceModule -ne 15 -or $targetBankId -le 0){throw 'Muhasebe kaynak baglantisi hatali.'}
   $result[$name]=$targetBankId;continue
  }
  $mapKind=switch($name){'BankAccountId'{'BankAccount'} 'GLAccountId'{'GLAccount'} 'AccountId'{'GLAccount'} 'ForexId'{'Forex'} 'TransactionForexId'{'Forex'} 'LedgerForexId'{'Forex'} default{$null}}
  if($mapKind){$key=$mapKind+':'+[string]$value;if(!$pair.Maps.ContainsKey($key)){throw "Referans eslesmedi: $name=$value"};$result[$name]=$pair.Maps[$key];continue}
  if(($name.EndsWith('Id') -or $name.EndsWith('Ids') -or $name.EndsWith('By')) -and [string]$value -ne '0'){throw "Desteklenmeyen baglanti: $kind.$name"}
  $result[$name]=$value
 }
 return $result
}
function New-BankPayload($pair) {
 $body=[ordered]@{Erp_BankReceipt=@(Convert-TransferRow $pair.Tables.BankHeader[0] $pair 'Bank');Erp_BankReceiptItem=@($pair.Tables.BankItems|ForEach-Object {Convert-TransferRow $_ $pair 'Bank'})}
 if($pair.Tables.BankAttachments.Count){$body.Erp_BankReceiptAttachment=@($pair.Tables.BankAttachments|ForEach-Object {Convert-TransferRow $_ $pair 'Bank'})}
 return $body
}
function New-GLPayload($pair,[long]$targetBankId) {
 return [ordered]@{Erp_GLReceipt=@(Convert-TransferRow $pair.Tables.GLHeader[0] $pair 'GL' $targetBankId);Erp_GLReceiptItem=@($pair.Tables.GLItems|ForEach-Object {Convert-TransferRow $_ $pair 'GL' $targetBankId})}
}
function Save-TransferState($path,$state){
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{$state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $temp -Encoding UTF8;if(Test-Path $path){[IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$path)}}finally{if(Test-Path $temp){Remove-Item -LiteralPath $temp}}
}
function Assert-TransferRows($actual,$expected,[string[]]$ignored){
 $a=@($actual);$e=@($expected | ForEach-Object { if($_ -is [System.Collections.IDictionary]){[pscustomobject]$_}else{$_} })
 if($a.Count -ne $e.Count){throw 'Kayit sonrasi satir sayisi uyusmuyor.'}
 if($e.Count -gt 1){
  if(@($e|Group-Object ItemOrderNo|Where-Object Count -gt 1).Count -or @($a|Group-Object ItemOrderNo|Where-Object Count -gt 1).Count){throw 'Tekrarli satir sirasi; dogrulama belirsiz.'}
  $a=@($a|Sort-Object ItemOrderNo);$e=@($e|Sort-Object ItemOrderNo)
 }
 for($n=0;$n -lt $e.Count;$n++){
  foreach($key in $e[$n].PSObject.Properties.Name){
   if($key -in $ignored){continue}
   if(!$a[$n].PSObject.Properties[$key]){throw "Hedef alan eksik: $key"}
   $left=$a[$n].$key;$right=$e[$n].$key
   if($null -eq $left -or $null -eq $right){if($null -ne $left -or $null -ne $right){throw "Alan uyusmuyor: $key"};continue}
   if($key -eq 'UniqueId'){if([guid]$left -ne [guid]$right){throw 'UniqueId uyusmuyor.'};continue}
   if($key -match 'Date$|Time$|At$'){if([datetime]$left -ne [datetime]$right){throw "Tarih uyusmuyor: $key"};continue}
   if($right -is [ValueType] -and $right -isnot [bool]){if([decimal]$left -ne [decimal]$right){throw "Sayisal alan uyusmuyor: $key"};continue}
   if([string]$left -cne [string]$right){throw "Alan uyusmuyor: $key"}
  }
 }
}
function Invoke-BankPairTransfer($pair,[scriptblock]$callApi,[string]$journalPath){
 # Caller performs fresh source hash/reference checks. This adapter checks the active target again.
 if(Test-Path $journalPath){throw 'Bu aktarimin durum dosyasi mevcut. Otomatik tekrar yasak; hedef kayitlari uzlastirilmali.'}
 $bankPayload=New-BankPayload $pair
 $null=New-GLPayload $pair 1 # Detect unsupported fields before the first write.
 $identity=& $callApi '/api/Utility/UtilityQuery' @{query="SELECT DB_NAME() DatabaseName,RecId,CompanyCode FROM dbo.Erp_Company WHERE RecId=7"}
 if(@($identity.Data).Count -ne 1 -or $identity.Data[0].DatabaseName -ne 'SentezLiveDev2024' -or $identity.Data[0].RecId -ne 7 -or $identity.Data[0].CompanyCode -ne '012018'){throw 'API hedef veritabani/sirketi hatali.'}
 $prm=& $callApi '/api/Parameters/Get?ParameterName=GLParameters' $null
 $values=if($prm.Data -is [string]){$prm.Data|ConvertFrom-Json}else{$prm.Data}
 if($values.BankReceiptIntegration -ne 2){throw 'Banka muhasebe entegrasyon ayari degisti; cift kayit riski nedeniyle durduruldu.'}
 $uid=([guid]$pair.UniqueId).ToString('D');$no=$pair.ReceiptNo.Replace("'","''");$gno=$pair.GLReceiptNo.Replace("'","''");$date=([datetime]$pair.GLReceiptDate).ToString('yyyyMMdd')
 $check=& $callApi '/api/Utility/UtilityQuery' @{query="SELECT (SELECT COUNT(*) FROM dbo.Erp_BankReceipt WHERE CompanyId=7 AND (UniqueId='$uid' OR (ReceiptType=$($pair.ReceiptType) AND ReceiptNo=N'$no'))) BankCount,(SELECT COUNT(*) FROM dbo.Erp_GLReceipt WHERE CompanyId=7 AND ReceiptType=$($pair.GLReceiptType) AND ReceiptNo=N'$gno' AND ReceiptDate='$date') GLCount"}
 if($check.Data[0].BankCount -ne 0 -or $check.Data[0].GLCount -ne 0){throw 'Hedefte ayni fis bulundu; yeni kayit engellendi.'}
 $state=[ordered]@{SourceDatabase='SentezLiveDev2025';TargetDatabase='SentezLiveDev2024';CompanyId=7;SourceBankId=$pair.BankId;SourceGLId=$pair.GLId;UniqueId=$uid;StartedAt=(Get-Date).ToString('o');Stage='BeforeBankPost';TargetBankId=$null;TargetGLId=$null;Failure=$null}
 Save-TransferState $journalPath $state
 try {
  $posted=& $callApi '/api/BO/PostBO?BOName=BankReceiptBO' $bankPayload
  $bankId=[long]$posted.Data;if($bankId -le 0){throw 'Banka API sonucu kayit kimligi icermiyor.'}
  $state.TargetBankId=$bankId;$state.Stage='BankPosted';Save-TransferState $journalPath $state
  $read=& $callApi ("/api/BO/GetByRecId?BoName=BankReceiptBO&RecId=$bankId") $null
  $h=@($read.Data.Erp_BankReceipt);$i=@($read.Data.Erp_BankReceiptItem)
  if($h.Count -ne 1 -or $h[0].CompanyId -ne 7 -or [guid]$h[0].UniqueId -ne [guid]$uid -or $h[0].ReceiptNo -ne $pair.ReceiptNo -or $i.Count -ne $pair.Tables.BankItems.Count -or $h[0].GLReceiptId){throw 'Banka kaydi okuma dogrulamasi basarisiz.'}
  Assert-TransferRows $h $bankPayload.Erp_BankReceipt @('RecId')
  Assert-TransferRows $i $bankPayload.Erp_BankReceiptItem @('RecId','BankReceiptId')
  foreach($row in $i){if($row.BankReceiptId -ne $bankId){throw 'Hedef banka satir sahipligi hatali.'}}
  if($pair.Tables.BankAttachments.Count){Assert-TransferRows $read.Data.Erp_BankReceiptAttachment $bankPayload.Erp_BankReceiptAttachment @('RecId','BankReceiptId')}
  $state.Stage='BeforeGLPost';Save-TransferState $journalPath $state
  $glPayload=New-GLPayload $pair $bankId
  $posted=& $callApi '/api/BO/PostBO?BOName=GLReceiptBO' $glPayload
  $glId=[long]$posted.Data;if($glId -le 0){throw 'Muhasebe API sonucu kayit kimligi icermiyor.'}
  $state.TargetGLId=$glId;$state.Stage='GLPosted';Save-TransferState $journalPath $state
  $read=& $callApi ("/api/BO/GetByRecId?BoName=GLReceiptBO&RecId=$glId") $null
  $h=@($read.Data.Erp_GLReceipt);$i=@($read.Data.Erp_GLReceiptItem)
  if($h.Count -ne 1 -or $h[0].CompanyId -ne 7 -or $h[0].SourceId -ne $bankId -or $h[0].ReceiptNo -ne $pair.GLReceiptNo -or $i.Count -ne $pair.Tables.GLItems.Count -or [decimal]$h[0].Debit -ne [decimal]$pair.Tables.GLHeader[0].Debit -or [decimal]$h[0].Credit -ne [decimal]$pair.Tables.GLHeader[0].Credit){throw 'Muhasebe kaydi okuma dogrulamasi basarisiz.'}
  Assert-TransferRows $h $glPayload.Erp_GLReceipt @('RecId')
  Assert-TransferRows $i $glPayload.Erp_GLReceiptItem @('RecId','GLReceiptId')
  foreach($row in $i){if($row.GLReceiptId -ne $glId){throw 'Hedef muhasebe satir sahipligi hatali.'}}
  $state.Stage='BeforeLink';Save-TransferState $journalPath $state
  $null=& $callApi ("/api/BO/UpdateBO?BOName=BankReceiptBO&RecId=$bankId") @{Erp_BankReceipt=@(@{RecId=$bankId;GLReceiptId=$glId})}
  $read=& $callApi ("/api/BO/GetByRecId?BoName=BankReceiptBO&RecId=$bankId") $null
  if($read.Data.Erp_BankReceipt[0].GLReceiptId -ne $glId){throw 'Banka muhasebe baglantisi dogrulanamadi.'}
  $state.Stage='Completed';$state.CompletedAt=(Get-Date).ToString('o');Save-TransferState $journalPath $state
  return [pscustomobject]$state
 }catch{$state.Failure=$_.Exception.Message;Save-TransferState $journalPath $state;throw}
}


