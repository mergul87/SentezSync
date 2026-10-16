using System.Collections.ObjectModel;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace SentezSync;
public sealed class TableInfo {
 public string Table {get;set;}=""; public string Status {get;set;}="";
 public long? SourceCount {get;set;} public long? TargetCount {get;set;}
 public bool HasCompanyId {get;set;} public bool SchemaMatches {get;set;}
 public long? Difference => SourceCount-TargetCount;
 public string DisplayStatus => Status switch {"CompanyScopedCandidate"=>"Şirket kapsamı / inceleme adayı", "OwnershipReview"=>"İlişki incelemesi gerekli", "SystemOrNonErpReview"=>"Sistem / diğer", "SchemaMismatch"=>"Kolon yapısı farklı", "MissingTargetTable"=>"Hedef tablo yok", "CountFailed"=>"Sayım hatası", _=>Status};
}
public record HistoryItem(string Time,string Kind,string Message);
public partial class MainWindow : Window {
 readonly string root; readonly DispatcherTimer timer=new(); readonly ObservableCollection<HistoryItem> history=new();
 List<TableInfo> tables=[]; bool busy,monitoring; string? reportDir;
 static readonly JsonSerializerOptions jsonOptions=new(){PropertyNameCaseInsensitive=true,WriteIndented=true};
 public MainWindow(){
  InitializeComponent(); root=FindRoot(); HistoryGrid.ItemsSource=history;
  timer.Tick+=async(_,_)=> {if(!busy && monitoring) await Inspect();}; timer.Interval=TimeSpan.FromSeconds(300);
  Closing+=(_,e)=>{if(busy){MessageBox.Show("Okuma işlemi devam ediyor. Önce tamamlanmasını bekleyin.");e.Cancel=true;}else timer.Stop();};
  Loaded+=(_,_)=>{try{LoadProfile();LoadHistory();LoadLatest();LoadComparison();LoadBankPlan();QueueGrid.ItemsSource=new ReviewQueue(Path.Combine(root,"review-queue.json")).Read();}catch(Exception ex){ShowError(ex);}};
 }
 static string FindRoot(){var d=new DirectoryInfo(AppContext.BaseDirectory);while(d!=null){if(File.Exists(Path.Combine(d.FullName,"profile.json")))return d.FullName;d=d.Parent;}return AppContext.BaseDirectory;}
 void LoadProfile(){
  var text=File.ReadAllText(Path.Combine(root,"profile.json"));ProfileText.Text=text;
  using var doc=JsonDocument.Parse(text);var p=doc.RootElement;
  RouteText.Text=$"{p.GetProperty("source").GetProperty("database").GetString()}  →  {p.GetProperty("target").GetProperty("database").GetString()}";
  var settings=Path.Combine(root,"desktop-settings.json");if(File.Exists(settings)){
   using var s=JsonDocument.Parse(File.ReadAllText(settings));int seconds=s.RootElement.GetProperty("IntervalSeconds").GetInt32();if(seconds>=60){timer.Interval=TimeSpan.FromSeconds(seconds);IntervalBox.Text=seconds.ToString();}
  }
 }
 void LoadHistory(){var path=Path.Combine(root,"history.jsonl");if(!File.Exists(path))return;foreach(var line in File.ReadLines(path).TakeLast(500)){try{var h=JsonSerializer.Deserialize<HistoryItem>(line);if(h!=null)history.Insert(0,h);}catch(JsonException){}}}
 void Log(string kind,string message){var h=new HistoryItem(DateTimeOffset.Now.ToString("yyyy-MM-dd HH:mm:ss zzz"),kind,message);history.Insert(0,h);while(history.Count>500)history.RemoveAt(history.Count-1);File.AppendAllText(Path.Combine(root,"history.jsonl"),JsonSerializer.Serialize(h)+Environment.NewLine);}
 void LoadLatest(){
  var path=Path.Combine(root,"reports");if(!Directory.Exists(path))return;
  var file=Directory.EnumerateFiles(path,"inspection.json",SearchOption.AllDirectories).OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
  if(file==null)return;using var d=JsonDocument.Parse(File.ReadAllText(file));var r=d.RootElement;
  tables=JsonSerializer.Deserialize<List<TableInfo>>(r.GetProperty("Tables").GetRawText(),jsonOptions)??[];
  reportDir=Path.GetDirectoryName(file);var src=r.GetProperty("Source");var tgt=r.GetProperty("Target");
  CompanyText.Text=$"Kaynak: {src.GetProperty("Code")} / {src.GetProperty("Name")}\nHedef: {tgt.GetProperty("Code")} / {tgt.GetProperty("Name")}";
  TableCount.Text=tables.Count.ToString();ScopedCount.Text=tables.Count(x=>x.Status=="CompanyScopedCandidate").ToString();
  DifferenceCount.Text=tables.Count(x=>x.Difference.HasValue && x.Difference!=0).ToString();ReviewCount.Text=tables.Count(x=>x.Status=="OwnershipReview").ToString();
  LastRunText.Text="Rapor zamanı: "+r.GetProperty("GeneratedAt").GetString();Filter();
 }
 void Filter(){if(TablesGrid==null)return;var search=SearchBox?.Text??"";TablesGrid.ItemsSource=tables.Where(x=>x.Table.Contains(search,StringComparison.OrdinalIgnoreCase) && (OnlyDifferent?.IsChecked!=true || (x.Difference.HasValue && x.Difference!=0))).ToList();}
 void Filter_Changed(object sender,RoutedEventArgs e)=>Filter();void Search_Changed(object sender,TextChangedEventArgs e)=>Filter();
 bool CheckCredential(){if(string.IsNullOrWhiteSpace(SqlUser.Text)||SqlPassword.SecurePassword.Length==0){MessageBox.Show("Bağlantı ve Ayarlar sekmesine SQL kullanıcı adı ve parolasını girin. Parola kaydedilmez.","SQL girişi gerekli");return false;}return true;}
 async Task<(int Code,string Output)> RunWorker(string mode,string? table=null,long? sourceRecId=null,long? targetRecId=null){
  var start=new ProcessStartInfo("powershell.exe"){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=root};
  start.Environment.Remove("PSModulePath");
  foreach(var arg in new[]{"-NoProfile","-NonInteractive","-File",Path.Combine(root,"Desktop-Worker.ps1"),"-Mode",mode})start.ArgumentList.Add(arg);
  if(table!=null){start.ArgumentList.Add("-Table");start.ArgumentList.Add(table);}
  if(sourceRecId.HasValue){start.ArgumentList.Add("-SourceRecId");start.ArgumentList.Add(sourceRecId.Value.ToString());}
  if(targetRecId.HasValue){start.ArgumentList.Add("-TargetRecId");start.ArgumentList.Add(targetRecId.Value.ToString());}
  using var process=Process.Start(start)??throw new InvalidOperationException("PowerShell başlatılamadı.");
  var output=process.StandardOutput.ReadToEndAsync();var error=process.StandardError.ReadToEndAsync();
  await process.StandardInput.WriteLineAsync(SqlUser.Text);
  await process.StandardInput.WriteLineAsync(SqlPassword.Password);process.StandardInput.Close();
  await process.WaitForExitAsync();return(process.ExitCode,(await output)+"\n"+(await error));
 }
 void SetBusy(bool value){busy=value;RunButton.IsEnabled=!value;StartButton.IsEnabled=!value&&!monitoring;StateText.Text=value?"SQL verileri okunuyor…":monitoring?"Otomatik izleme açık • SQL yazma kapalı":"Otomatik izleme kapalı • SQL yazma kapalı";}
 async Task Inspect(){
  if(busy||!CheckCredential())return;SetBusy(true);Log("Karşılaştırma","Salt okunur inceleme başladı.");
  try{var result=await RunWorker("Inspect");if(result.Code!=0)throw new InvalidOperationException(result.Output.Trim());LoadLatest();Log("Tamamlandı",$"{tables.Count} tablo incelendi; {tables.Count(x=>x.Difference.HasValue&&x.Difference!=0)} tabloda sayı farkı var.");}
  catch(Exception ex){monitoring=false;timer.Stop();StopButton.IsEnabled=false;ShowError(ex);}
  finally{SetBusy(false);}
 }
 async void Run_Click(object sender,RoutedEventArgs e)=>await Inspect();
 async void Start_Click(object sender,RoutedEventArgs e){if(busy||!CheckCredential())return;if(!ReadInterval())return;monitoring=true;StartButton.IsEnabled=false;StopButton.IsEnabled=true;timer.Start();Log("İzleme","Periyodik SQL okuma başlatıldı. Aktarım kapalı.");await Inspect();}
 void Stop_Click(object sender,RoutedEventArgs e){monitoring=false;timer.Stop();StopButton.IsEnabled=false;StartButton.IsEnabled=!busy;StateText.Text=busy?"Durduruluyor: devam eden okuma tamamlanacak.":"Otomatik izleme kapalı";Log("İzleme","Yeni okumalar durduruldu; devam eden okuma varsa tamamlanacak.");}
 bool ReadInterval(){if(!int.TryParse(IntervalBox.Text,out var seconds)||seconds<60||seconds>86400){MessageBox.Show("Kontrol aralığı 60–86400 saniye olmalı.");return false;}timer.Interval=TimeSpan.FromSeconds(seconds);return true;}
 void SaveInterval_Click(object sender,RoutedEventArgs e){if(!ReadInterval())return;try{File.WriteAllText(Path.Combine(root,"desktop-settings.json"),JsonSerializer.Serialize(new{IntervalSeconds=(int)timer.Interval.TotalSeconds},jsonOptions));Log("Ayar","Kontrol aralığı güncellendi.");}catch(Exception ex){ShowError(ex);}}
 void OpenReport_Click(object sender,RoutedEventArgs e){if(reportDir!=null)Process.Start(new ProcessStartInfo("explorer.exe"){ArgumentList={reportDir},UseShellExecute=true});}
 void ShowError(Exception ex){var message=ex.Message;if(SqlPassword.Password.Length>0)message=message.Replace(SqlPassword.Password,"[gizli]");Log("Hata",message);MessageBox.Show(message,"İşlem tamamlanamadı",MessageBoxButton.OK,MessageBoxImage.Warning);}
 Snapshot? snapshot;
 List<ComparisonIssue> comparisonIssues=[];
 void LoadComparison(){
  var file=Path.Combine(root,"comparison-snapshot.json");if(!File.Exists(file))return;
  var candidate=JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(file),jsonOptions)??throw new InvalidDataException("Kayıt karşılaştırması okunamadı.");
  var comparison=ComparisonEngine.Compare(candidate);snapshot=candidate;comparisonIssues=comparison.Issues;
  DifferencesGrid.ItemsSource=comparison.Differences;
  ComparisonSummary.Text=$"{candidate.Table} • {candidate.GeneratedAt}\nKaynak {comparison.SourceCount:N0} / Hedef {comparison.TargetCount:N0} • Eşit özet {comparison.EqualCount:N0} • Fark {comparison.Differences.Count:N0} • Sorunlu kayıt {comparison.Issues.Count:N0} • Eşleştirme: {candidate.KeyColumn}";
  QueueGrid.ItemsSource=new ReviewQueue(Path.Combine(root,"review-queue.json")).Reconcile(candidate,comparison);
 }
 void Issues_Click(object sender,RoutedEventArgs e){new Window{Owner=this,Title="Eşleştirme dışında tutulan kayıtlar",Width=1000,Height=500,WindowStartupLocation=WindowStartupLocation.CenterOwner,Content=new DataGrid{AutoGenerateColumns=true,ItemsSource=comparisonIssues,IsReadOnly=true,CanUserAddRows=false}}.Show();}
 async void Compare_Click(object sender,RoutedEventArgs e){
  if(busy||!CheckCredential())return;var table=(CompareTable.SelectedItem as ComboBoxItem)?.Tag?.ToString();if(table==null)return;
  SetBusy(true);try{var result=await RunWorker("Compare",table);if(result.Code!=0)throw new InvalidOperationException(result.Output.Trim());LoadComparison();Log("Kayıt farkları",table+" tüm şirket kayıtları kod ve alan özetiyle karşılaştırıldı.");}catch(Exception ex){ShowError(ex);}finally{SetBusy(false);}
 }
 void Stage_Click(object sender,RoutedEventArgs e){
  if(busy)return;var items=DifferencesGrid.SelectedItems.Cast<RecordDifference>().ToList();if(items.Count==0){MessageBox.Show("Önce fark listesinden kayıt seçin.");return;}
  try{QueueGrid.ItemsSource=new ReviewQueue(Path.Combine(root,"review-queue.json")).Stage(items);Log("İnceleme kuyruğu",$"{items.Count} aday işlendi; aynı sürümler tekrar eklenmedi. SQL aktarımı yapılmadı.");}catch(Exception ex){ShowError(ex);}
 }
 async void VerifyQueue_Click(object sender,RoutedEventArgs e){
  if(busy||!CheckCredential())return;
  if(QueueGrid.SelectedItem is not ReviewTask selected){MessageBox.Show("Önce inceleme kuyruğundan bir kayıt seçin.");return;}
  SetBusy(true);try{
   var result=await RunWorker("Compare",selected.Table);if(result.Code!=0)throw new InvalidOperationException(result.Output.Trim());
   LoadComparison();var fresh=JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(Path.Combine(root,"comparison-snapshot.json")),jsonOptions)??throw new InvalidDataException("Yeni karşılaştırma okunamadı.");
   var updated=new ReviewQueue(Path.Combine(root,"review-queue.json")).Verify(selected.Id,fresh,DateTimeOffset.Now);QueueGrid.ItemsSource=updated;
   var task=updated.Single(x=>x.Id==selected.Id);Log("Kuyruk ön kontrolü",task.MatchKey+": "+task.VerificationText+". SQL yazma yapılmadı.");
   MessageBox.Show(task.VerificationText+"\n\nBu kontrol yalnız kaydın güncelliğini denetler. Bağlı kayıtlar ve API yazma adaptörü henüz doğrulanmadığı için aktarım yapmaz.","Ön kontrol sonucu");
  }catch(Exception ex){ShowError(ex);}finally{SetBusy(false);}
 }
 async void Detail_Click(object sender,RoutedEventArgs e){
  if(busy||!CheckCredential())return;if(DifferencesGrid.SelectedItem is not RecordDifference selected){MessageBox.Show("Önce bir kayıt seçin.");return;}
  SetBusy(true);try{
   var result=await RunWorker("Detail",selected.Table,selected.SourceRecId??0,selected.TargetRecId??0);if(result.Code!=0)throw new InvalidOperationException(result.Output.Trim());
   using var doc=JsonDocument.Parse(File.ReadAllText(Path.Combine(root,"record-detail.json")));var a=doc.RootElement.GetProperty("Source");var b=doc.RootElement.GetProperty("Target");
   var source=a.GetArrayLength()==0?new Dictionary<string,string?>():a[0].EnumerateObject().ToDictionary(p=>p.Name,p=>p.Value.ValueKind==JsonValueKind.Null?null:p.Value.ToString());
   var target=b.GetArrayLength()==0?new Dictionary<string,string?>():b[0].EnumerateObject().ToDictionary(p=>p.Name,p=>p.Value.ValueKind==JsonValueKind.Null?null:p.Value.ToString());
   var rows=source.Keys.Union(target.Keys).Where(k=>source.GetValueOrDefault(k)!=target.GetValueOrDefault(k)||source.ContainsKey(k)!=target.ContainsKey(k)).Select(k=>new{Alan=k,Kaynak=source.ContainsKey(k)?source[k]??"[NULL]":"[kayıt yok]",Hedef=target.ContainsKey(k)?target[k]??"[NULL]":"[kayıt yok]"}).ToList();
   var panel=new DockPanel{Margin=new Thickness(16)};var note=new TextBlock{Text="Güncel alan değerleri • Teknik alanlar da gösterilir. Karşılaştırmadan sonra veriler değişmiş olabilir. Bu görünüm yazma onayı değildir.",TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,0,0,12)};DockPanel.SetDock(note,Dock.Top);panel.Children.Add(note);
   panel.Children.Add(new DataGrid{AutoGenerateColumns=true,ItemsSource=rows,IsReadOnly=true,CanUserAddRows=false});
   new Window{Owner=this,Title=selected.MatchKey+" — Alan farkları",Width=1100,Height=650,Content=panel,WindowStartupLocation=WindowStartupLocation.CenterOwner}.Show();
   Log("Alan farkları",selected.Table+" / "+selected.MatchKey+": "+rows.Count+" alan farklı.");
  }catch(Exception ex){ShowError(ex);}finally{SetBusy(false);}
 }
 async void Rows_Click(object sender,RoutedEventArgs e){
  if(busy)return;if(TablesGrid.SelectedItem is not TableInfo t){MessageBox.Show("Önce bir tablo seçin.");return;}
  if(t.Status!="CompanyScopedCandidate"){MessageBox.Show("Bu tablo için şirket sahipliği veya kolon uyumu henüz doğrulanmadı.");return;}if(!CheckCredential())return;
  SetBusy(true);try{var r=await RunWorker("Rows",t.Table);if(r.Code!=0)throw new InvalidOperationException(r.Output.Trim());
   using var d=JsonDocument.Parse(File.ReadAllText(Path.Combine(root,"row-preview.json")));
   var tabs=new TabControl();foreach(var side in new[]{"Source","Target"}){var data=new DataTable();var rows=d.RootElement.GetProperty(side);if(rows.GetArrayLength()>0){foreach(var p in rows[0].EnumerateObject())data.Columns.Add(p.Name);foreach(var row in rows.EnumerateArray()){var dr=data.NewRow();foreach(var p in row.EnumerateObject())dr[p.Name]=p.Value.ValueKind==JsonValueKind.Null?"":p.Value.ToString();data.Rows.Add(dr);}}
    tabs.Items.Add(new TabItem{Header=side=="Source"?"Kaynak • ilk 200 kayıt":"Hedef • ilk 200 kayıt",Content=new DataGrid{ItemsSource=data.DefaultView,AutoGenerateColumns=true,IsReadOnly=true,CanUserAddRows=false}});
   }
   var panel=new DockPanel{Margin=new Thickness(16)};var note=new TextBlock{Text="Şirket 7 • Bu görünüm örnek kayıtlardır; kayıtlar eşleştirilmiş veya alan farkları hesaplanmış değildir.",Margin=new Thickness(0,0,0,12),TextWrapping=TextWrapping.Wrap};DockPanel.SetDock(note,Dock.Top);panel.Children.Add(note);panel.Children.Add(tabs);
   new Window{Owner=this,Title=t.Table+" — Veri Görünümü",Width=1100,Height=650,Content=panel,WindowStartupLocation=WindowStartupLocation.CenterOwner}.Show();Log("Veri görüntüleme",t.Table+" kaynak/hedef örnek kayıtları okundu.");
  }catch(Exception ex){ShowError(ex);}finally{SetBusy(false);}
 }
}

