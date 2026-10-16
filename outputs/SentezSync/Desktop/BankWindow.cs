using System.IO;
using System.Text.Json;
using System.Windows;

namespace SentezSync;
public partial class MainWindow {
 List<BankPlanRow> bankPlan=[];
 async void BankCompare_Click(object sender,RoutedEventArgs e){
  if(busy||!CheckCredential())return;
  SetBusy(true);
  try{
   var result=await RunWorker("BankPlan");if(result.Code!=0)throw new InvalidOperationException(result.Output.Trim());
   LoadBankPlan();Log("Banka fişleri",BankSummary.Text);
  }catch(Exception ex){ShowError(ex);}finally{SetBusy(false);}
 }
 void LoadBankPlan(){
  var path=Path.Combine(root,"bank-snapshot.json");if(!File.Exists(path))return;
  var snapshot=JsonSerializer.Deserialize<BankSnapshot>(File.ReadAllText(path),jsonOptions)??throw new InvalidDataException("Banka verileri okunamadı.");
  bankPlan=BankPlanner.Build(snapshot);
  BankSummary.Text=$"{snapshot.GeneratedAt} • Kaynak {snapshot.Source.Count:N0} / Hedef {snapshot.Target.Count:N0}\n"+string.Join(" • ",bankPlan.GroupBy(x=>x.Status).Select(g=>$"{g.Key}: {g.Count():N0}"));
  FilterBank();
 }
 void BankFilter_Changed(object sender,RoutedEventArgs e)=>FilterBank();
 void FilterBank(){if(BankGrid!=null)BankGrid.ItemsSource=bankPlan.Where(x=>BankOnlyDifferences?.IsChecked!=true||x.Status!="Eşit özet").ToList();}
}
