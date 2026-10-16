using System.IO;
using System.Text.Json.Serialization;

namespace SentezSync;
public sealed class BankSnapshot {
 public string Route {get;set;}="";
 public string StartedAt {get;set;}="";
 public string GeneratedAt {get;set;}="";
 public List<BankRow> Source {get;set;}=[];
 public List<BankRow> Target {get;set;}=[];
}
public sealed class BankRow {
 public long RecId {get;set;}
 public string? UniqueId {get;set;}
 public int ReceiptType {get;set;}
 public string? ReceiptNo {get;set;}
 public string? ReceiptDate {get;set;}
 public long? InsertedBy {get;set;}
 public string? Creator {get;set;}
 public long? UpdatedBy {get;set;}
 public string? Updater {get;set;}
 public long? GLReceiptId {get;set;}
 public long? SourceId {get;set;}
 public int? SourceModule {get;set;}
 public int IsDeleted {get;set;}
 public int ItemCount {get;set;}
 public int AttachmentCount {get;set;}
 public int InvalidBankReferences {get;set;}
 public int InvalidGLReference {get;set;}
 public string HeaderHash {get;set;}="";
 public string ItemsHash {get;set;}="";
 public string AttachmentsHash {get;set;}="";
 [JsonIgnore] public string? Identity {
  get {
   if(Guid.TryParse(UniqueId,out var id)&&id!=Guid.Empty)return id.ToString("D");
   if(!string.IsNullOrWhiteSpace(UniqueId)||string.IsNullOrWhiteSpace(ReceiptNo)||ReceiptNo!=ReceiptNo.Trim())return null;
   if(!DateTime.TryParse(ReceiptDate,System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.RoundtripKind,out var date))return null;
   return "legacy|"+BusinessKey+"|"+date.ToString("yyyy-MM-dd");
  }
 }
 [JsonIgnore] public string BusinessKey=>ReceiptType+"|"+(ReceiptNo??"").Trim();
}
public sealed record BankPlanRow(string Status,string ReceiptNo,int ReceiptType,long? SourceRecId,long? TargetRecId,string? SourceCreator,string? TargetCreator,int SourceItems,int TargetItems,string Differences,string BlockReason,string MatchMethod);
public static class BankPlanner {
 public static List<BankPlanRow> Build(BankSnapshot snapshot){
  if(string.IsNullOrWhiteSpace(snapshot.Route))throw new InvalidDataException("Banka karşılaştırmasının bağlantı bilgisi eksik.");
  foreach(var r in snapshot.Source.Concat(snapshot.Target)){
   const string empty="E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855";
   if(r.ItemsHash==null&&r.ItemCount==0)r.ItemsHash=empty;
   if(r.AttachmentsHash==null&&r.AttachmentCount==0)r.AttachmentsHash=empty;
   if(r.RecId<=0||new[]{r.HeaderHash,r.ItemsHash,r.AttachmentsHash}.Any(h=>h==null||h.Length!=64||!h.All(Uri.IsHexDigit)))throw new InvalidDataException("Banka kayıt özeti geçersiz.");
  }
  var result=new List<BankPlanRow>();
  var source=snapshot.Source.Where(x=>x.Identity!=null).GroupBy(x=>x.Identity!).ToDictionary(g=>g.Key,g=>g.ToList());
  var target=snapshot.Target.Where(x=>x.Identity!=null).GroupBy(x=>x.Identity!).ToDictionary(g=>g.Key,g=>g.ToList());
  var duplicateCodes=snapshot.Source.GroupBy(x=>x.BusinessKey).Where(g=>g.Count()>1).Select(g=>g.Key).Concat(snapshot.Target.GroupBy(x=>x.BusinessKey).Where(g=>g.Count()>1).Select(g=>g.Key)).ToHashSet();
  var targetCodes=snapshot.Target.GroupBy(x=>x.BusinessKey).ToDictionary(g=>g.Key,g=>g.ToList());
  var sourceCodes=snapshot.Source.GroupBy(x=>x.BusinessKey).ToDictionary(g=>g.Key,g=>g.ToList());
  foreach(var key in source.Keys.Union(target.Keys).Order()){
   var a=source.GetValueOrDefault(key)??[];var b=target.GetValueOrDefault(key)??[];
   if(a.Count>1||b.Count>1){foreach(var x in a)result.Add(Row(x,null,"Engelli","","Tekrarlı eşleştirme anahtarı."));foreach(var x in b)result.Add(Row(null,x,"Engelli","","Tekrarlı eşleştirme anahtarı."));continue;}
   BankRow? s=a.SingleOrDefault(),t=b.SingleOrDefault();var r=s??t!;
   var reasons=new List<string>();
   if(duplicateCodes.Contains(r.BusinessKey))reasons.Add("Aynı tür/fiş numarası birden fazla kayıtta var.");
   if(string.IsNullOrWhiteSpace(r.ReceiptNo)||r.ReceiptNo!=r.ReceiptNo.Trim())reasons.Add("Fiş numarası boş veya kenar boşluklu.");
   if(s!=null&&t!=null&&s.BusinessKey!=t.BusinessKey)reasons.Add("Aynı UniqueId farklı fiş numarası/türü taşıyor.");
   if(s!=null&&t==null&&targetCodes.ContainsKey(s.BusinessKey)||t!=null&&s==null&&sourceCodes.ContainsKey(t.BusinessKey))reasons.Add("Fiş numarası karşı tarafta farklı UniqueId ile var.");
   foreach(var record in new[]{s,t}.OfType<BankRow>()){
    if(record.InvalidBankReferences>0||record.InvalidGLReference>0)reasons.Add("Eksik veya başka şirkete bağlı banka/muhasebe referansı.");
   }
   var differences=new List<string>();
   if(s!=null&&t!=null){if(s.HeaderHash!=t.HeaderHash)differences.Add("Başlık");if(s.ItemsHash!=t.ItemsHash)differences.Add("Hareketler");if(s.AttachmentsHash!=t.AttachmentsHash)differences.Add("Ekler");}
   string status=reasons.Count>0?"Engelli":s==null?"Yalnız hedef":t==null?"Yalnız kaynak":differences.Count==0?"Eşit özet":"İçerik farklı";
   if(s!=null&&t==null){
    if(s.ItemCount==0)reasons.Add("Satırsız fiş; otomatik aktarıma uygun değil.");
    if(s.IsDeleted!=0)reasons.Add("Kaynak silinmiş işaretli; ilk eşitlemede oluşturulmaz.");
    if(s.GLReceiptId.HasValue)reasons.Add("Muhasebe fişi eşleştirmesi gerekli.");
    if(s.SourceId.HasValue)reasons.Add("Kaynak belge bağlantısı eşleştirilmeli.");
    reasons.Add("Banka iş nesnesi yazma adaptörü henüz doğrulanmadı.");
   }
   if(s==null)reasons.Add("Hedefte korunur. Kaynakta olmaması silme kanıtı değildir.");
   if(s!=null&&t!=null&&differences.Count>0)reasons.Add("Bağlı kimlikler normalleştirilmedi; otomatik üzerine yazılmaz.");
   result.Add(Row(s,t,status,string.Join(", ",differences),string.Join(" ",reasons.Distinct())));
  }
  foreach(var r in snapshot.Source.Where(x=>x.Identity==null))result.Add(Row(r,null,"Engelli","","Geçerli UniqueId veya eski kayıt anahtarı yok."));
  foreach(var r in snapshot.Target.Where(x=>x.Identity==null))result.Add(Row(null,r,"Engelli","","Geçerli UniqueId veya eski kayıt anahtarı yok."));
  return result;
 }
 static BankPlanRow Row(BankRow? s,BankRow? t,string status,string differences,string reason)=>new(status,(s??t)!.ReceiptNo??"",(s??t)!.ReceiptType,s?.RecId,t?.RecId,s?.Creator,t?.Creator,s?.ItemCount??0,t?.ItemCount??0,differences,reason,(s??t)!.Identity?.StartsWith("legacy|")==true?"Tür + numara + tarih":"UniqueId");
}
