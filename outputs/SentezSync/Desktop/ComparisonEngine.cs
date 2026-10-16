using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SentezSync;
public record FingerprintRow(long RecId,string? MatchKey,string Fingerprint);
public sealed class Snapshot {
 public string Table {get;set;}=""; public string KeyColumn {get;set;}="";
 public string Route {get;set;}=""; public string GeneratedAt {get;set;}="";
 public List<FingerprintRow> Source {get;set;}=[]; public List<FingerprintRow> Target {get;set;}=[];
}
public sealed class RecordDifference {
 public string Table {get;set;}=""; public string MatchKey {get;set;}=""; public string Kind {get;set;}="";
 public long? SourceRecId {get;set;} public long? TargetRecId {get;set;}
 public string? SourceHash {get;set;} public string? TargetHash {get;set;}
 public string Route {get;set;}="";
 public string DisplayKind=>Kind switch {"SourceOnly"=>"Yalnız kaynak", "TargetOnly"=>"Yalnız hedef • silme kanıtı değil", "Different"=>"Alanlar farklı • yön belirsiz", _=>Kind};
 public string Id=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new{Route,Table,MatchKey,Kind,SourceHash,TargetHash}))));
}
public record ComparisonIssue(string Side,long RecId,string? MatchKey,string Reason);
public record ComparisonResult(int SourceCount,int TargetCount,int EqualCount,List<RecordDifference> Differences,List<ComparisonIssue> Issues);
public static class ComparisonEngine {
 static Dictionary<string,FingerprintRow> Index(List<FingerprintRow> rows,string side,HashSet<string> blocked,List<ComparisonIssue> issues){
  var result=new Dictionary<string,FingerprintRow>(StringComparer.Ordinal);
  foreach(var r in rows){
   if(r.Fingerprint.Length!=64||!r.Fingerprint.All(Uri.IsHexDigit))throw new InvalidDataException(side+": geçersiz kayıt özeti.");
   if(string.IsNullOrWhiteSpace(r.MatchKey)||blocked.Contains(r.MatchKey.Trim())){issues.Add(new(side,r.RecId,r.MatchKey,"Boş, kenar boşluklu veya tekrarlı kod; iki taraftaki karşılıkları eşleştirmeden çıkarıldı."));continue;}
   result.Add(r.MatchKey,r);
  }
  return result;
 }
 public static ComparisonResult Compare(Snapshot s){
  if(string.IsNullOrWhiteSpace(s.Route)||string.IsNullOrWhiteSpace(s.Table))throw new InvalidDataException("Karşılaştırma bağlamı eksik.");
  var blocked=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  foreach(var rows in new[]{s.Source,s.Target}){
   foreach(var row in rows.Where(x=>!string.IsNullOrEmpty(x.MatchKey)&&x.MatchKey!=x.MatchKey.Trim()))blocked.Add(row.MatchKey!.Trim());
   foreach(var group in rows.GroupBy(x=>x.MatchKey?.Trim()??"",StringComparer.OrdinalIgnoreCase).Where(x=>x.Count()>1))blocked.Add(group.Key);
  }
  var issues=new List<ComparisonIssue>();var a=Index(s.Source,"Kaynak",blocked,issues);var b=Index(s.Target,"Hedef",blocked,issues);var differences=new List<RecordDifference>();int equal=0;
  foreach(var key in a.Keys.Union(b.Keys,StringComparer.Ordinal).Order(StringComparer.Ordinal)){
   a.TryGetValue(key,out var src);b.TryGetValue(key,out var dst);
   if(src!=null&&dst!=null&&src.Fingerprint==dst.Fingerprint){equal++;continue;}
   differences.Add(new RecordDifference{Table=s.Table,Route=s.Route,MatchKey=key,Kind=src==null?"TargetOnly":dst==null?"SourceOnly":"Different",SourceRecId=src?.RecId,TargetRecId=dst?.RecId,SourceHash=src?.Fingerprint,TargetHash=dst?.Fingerprint});
  }
  return new(s.Source.Count,s.Target.Count,equal,differences,issues);
 }
}
public sealed class ReviewTask {
 public string Id {get;set;}=""; public RecordDifference Difference {get;set;}=new();
 public string Status {get;set;}="AwaitingAdapter"; public string CreatedAt {get;set;}="";
 public string? VerifiedAt {get;set;}
 public string Verification {get;set;}="NotChecked";
 public string VerificationText=>Verification switch {"UnchangedSourceOnly"=>"Kaynak aynı; hedefte hâlâ yok", "ConflictNeedsPolicy"=>"Alan farkı var; değişiklik yönü doğrulanmalı", "DeletionNotProven"=>"Silme olayı kanıtlanmadı", "ChangedSinceReview"=>"Kayıt değişti veya eşleştirme sorunlu", _=>"Güncel kontrol yapılmadı"};
 public string Table=>Difference.Table;public string MatchKey=>Difference.MatchKey;
 public string Kind=>Difference.DisplayKind;
 public string DisplayStatus=>Status=="Stale"?"Eski karşılaştırma • tekrar incelenmeli":Status=="AwaitingAdapter"?"İnceleme • yazma adaptörü bekleniyor":"İnceleme";
}
public sealed class ReviewQueue(string path) {
 static readonly JsonSerializerOptions Options=new(){WriteIndented=true};
 public List<ReviewTask> Read(){if(!File.Exists(path))return [];return JsonSerializer.Deserialize<List<ReviewTask>>(File.ReadAllText(path))??throw new InvalidDataException("Kuyruk dosyası okunamadı.");}
 public List<ReviewTask> Stage(IEnumerable<RecordDifference> items){
  var queue=Read();foreach(var d in items){
   if(queue.Any(x=>x.Id==d.Id))continue;
   foreach(var old in queue.Where(x=>x.Difference.Route==d.Route&&x.Table==d.Table&&x.MatchKey==d.MatchKey))old.Status="Stale";
   queue.Add(new ReviewTask{Id=d.Id,Difference=d,CreatedAt=DateTimeOffset.Now.ToString("o")});
  }
  Save(queue);return queue;
 }
 public List<ReviewTask> Reconcile(Snapshot snapshot,ComparisonResult comparison){
  var current=comparison.Differences.Select(x=>x.Id).ToHashSet();var queue=Read();
  foreach(var item in queue.Where(x=>x.Difference.Route==snapshot.Route&&x.Table==snapshot.Table)){
   item.Status=current.Contains(item.Id)?"AwaitingAdapter":"Stale";
   if(item.Status=="Stale"){item.VerifiedAt=null;item.Verification="ChangedSinceReview";}
  }
  Save(queue);return queue;
 }
 public List<ReviewTask> Verify(string taskId,Snapshot fresh,DateTimeOffset now){
  if(!DateTimeOffset.TryParse(fresh.GeneratedAt,out var generated)||generated>now.AddSeconds(30)||now-generated>TimeSpan.FromMinutes(5))throw new InvalidDataException("Ön kontrol için yeni SQL okuması gerekli; rapor zamanı eski veya geçersiz.");
  var queue=Read();var item=queue.SingleOrDefault(x=>x.Id==taskId)??throw new InvalidDataException("Kuyruk kaydı bulunamadı.");
  if(item.Difference.Route!=fresh.Route||item.Table!=fresh.Table)throw new InvalidDataException("Ön kontrol kaynak/hedef bağlamı kuyrukla uyuşmuyor.");
  var result=ComparisonEngine.Compare(fresh);var current=result.Differences.SingleOrDefault(x=>x.Id==taskId);
  item.VerifiedAt=now.ToString("o");
  if(current==null){item.Status="Stale";item.Verification="ChangedSinceReview";}
  else{item.Status="AwaitingAdapter";item.Verification=current.Kind switch {"SourceOnly"=>"UnchangedSourceOnly","TargetOnly"=>"DeletionNotProven",_=>"ConflictNeedsPolicy"};}
  Save(queue);return queue;
 }
 void Save(List<ReviewTask> queue){
  Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
  var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
  try{using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){JsonSerializer.Serialize(stream,queue,Options);stream.Flush(true);}File.Move(temp,path,true);}
  finally{if(File.Exists(temp))File.Delete(temp);}
 }
}
