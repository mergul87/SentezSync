# SentezSync masaüstü sürümü — 15 Ekim 2026

## Açılış

`app/SentezSync.exe` dosyasını açın. EXE'yi klasörden tek başına taşımayın; app içindeki DLL/JSON dosyaları ile üst klasördeki profile.json, PowerShell betikleri ve reports klasörü birlikte gereklidir. Bu bilgisayardaki .NET 9 Windows Desktop çalışma ortamını kullanır.

## Çalışan özellikler

- Son gerçek SQL karşılaştırmasının otomatik yüklenmesi; 488 tablo, 127 doğrudan şirket bağlantılı tablo ve son sayımda 10 sayı farkı.
- Tablo adına göre filtreleme ve yalnız farklı sayıları gösterme.
- Seçili, doğrulanmış şirket kapsamlı ERP tablosunda kaynak/hedef ilk 200 kaydın ayrı sekmelerde görüntülenmesi. Bu örnekler henüz satır/alan eşleştirmesi değildir.
- SQL kullanıcı adı ve parolasını yalnız oturumda tutma. Alt sürece gizli standart giriş kanalıyla gönderme; komut satırında veya ayar dosyasında saklamama.
- Şimdi karşılaştır; periyodik izlemeyi başlat/durdur. Durdur, yeni okumaları engeller; devam eden okumayı tamamlar. Hata halinde otomatik izleme durur.
- 60–86400 saniye aralık ayarı, kalıcı işlem geçmişi ve rapor klasörüne erişim.

## Henüz çalışmayan özellikler

**Otomatik veri aktarımı ve hedefe kayıt yazma/silme henüz uygulanmadı.** Cari/stok kayıt farkları ve kalıcı inceleme kuyruğu ikinci sürümde eklendi; ayrıntıları aşağıdadır. Başlat/Durdur yalnız otomatik SQL okumayı kontrol eder.

Aktarım için 210 ERP detay/ortak tablonun şirket sahipliği, kayıt kimliği eşleştirmeleri, Sentez iş nesnesi yazma adaptörü, değişiklik/silme yakalama ve hedef çakışma politikası tamamlanmalıdır. Veriler farklı sayıda diye doğrudan hedef kaydı silmek veya kimlik numarasını kopyalamak doğru değildir.

## Doğrulamalar

- .NET Release derlemesi başarılı.
- Uygulama açılışı, gerçek rapor yükleme ve WPF ekran render testi başarılı.
- Desktop-Worker üzerinden gerçek SQL'de kaynak ve hedeften 200'er cari kart okundu; her iki örnekte CompanyId yalnız 7 olarak doğrulandı.
- SQL parola komut satırına veya dosyaya kaydedilmedi. Veri görüntüleme örnekleri row-preview.json dosyasında yerel tutulur; iş verisi içerir.
- Yeni sürümde hedef SQL'e INSERT, UPDATE veya DELETE uygulanmadı.

## Kaynak

Desktop klasörü düzenlenebilir C#/WPF kaynaklarını içerir. Derleme için .NET 9 SDK gereklidir. Inspect-Sentez.ps1 mevcut salt okunur inceleme aracıdır; Desktop-Worker.ps1 arayüzün okuma köprüsüdür.

## Kayıt karşılaştırma ve inceleme kuyruğu — ikinci sürüm

Yeni Kayıt Farkları sekmesinde cari ve stok kartlarının şirket 7 kapsamındaki tüm kayıtları kod bazında eşleştirilir. Teknik RecId, CompanyId, InsertedAt/By ve UpdatedAt/By alanları özetten çıkarılır; kalan kolonlar SHA-256 özetiyle karşılaştırılır. İlişkili kayıt kimlikleri henüz normalleştirilmez; eşit özet yalnız bu alanların aynı olduğunu gösterir. İki veritabanı ayrı zamanlarda okunur; eşzamanlı işlem varsa sonrasında yeniden kontrol gerekir.

- Yalnız kaynak / yalnız hedef / alanları farklı sınıfları gösterilir. Farklı kaydın hangi tarafta değiştiği ilk karşılaştırmadan anlaşılamaz.
- Alan farkları düğmesi seçili kaydın güncel kaynak ve hedef alanlarını gösterir; teknik alanlar burada görünür.
- Boş, tekrarlı veya kenar boşluklu kodlar iki tarafta da otomatik eşleştirme dışında tutulur; Eşleştirme sorunları düğmesinden incelenir.
- Seçilen farklar kalıcı review-queue.json dosyasına alınabilir. Aynı bağlam ve aynı içerik tekrar eklenmez. Sonraki karşılaştırmada değişmiş veya kaybolmuş farklar eski olarak işaretlenir.
- Bu bir İNCELEME kuyruğudur; hedefe yazma adaptörü henüz yoktur. Hedefte tek başına bulunmak silme kanıtı değildir.
- Kuyruk atomik dosya değişimiyle saklanır; bozuk dosya boş kuyruk gibi kabul edilmez. Tek uygulama örneği çalışır.

Doğrulanan sonuçlar (15 Ekim 2026): Cari kaynak 24.417 / hedef 24.413; 24.412 eşit alan özeti, yalnız kaynakta 4 kart, her tarafta birer aynı kod-boşluğu sorunu. Stok kaynak/hedef 3.056; tüm karşılaştırılan alan özetleri eşit, eşleştirme sorunu yok. Alan ayrıntısı testi kaynakta 1, hedefte 0 kayıt ve CompanyId 7 döndürdü. Bunlar okuma anındaki sonuçlardır.

Eşleştirme, mükerrer görev önleme, yeniden açınca kuyruk koruma, bağlam ayrımı, eski farkları geçersizleştirme ve bozuk dosyada durma testleri geçti. Windows PowerShell Türkçe kültüründe büyük I içeren tablo adlarının doğrulanması düzeltildi.


## Kuyruk güncellik ön kontrolü — üçüncü sürüm

İnceleme Kuyruğu sekmesindeki **Seçili kaydı güncel verilerle doğrula** düğmesi, ilgili tablonun yeni SQL karşılaştırmasını alır ve seçili adayı tekrar denetler. Kaynak/hedef bağlamı farklıysa veya rapor beş dakikadan eskiyse doğrulamaz. Kayıt değişmiş, eşitlenmiş, eşleştirme dışında kalmış veya hedefte sonradan oluşmuşsa aday eski durumuna geçer. Doğrulama zamanı ve açıklaması kuyrukta saklanır. Bu kontrol yazma yetkisi veya yazma anında kilit değildir; aktarım anında tekrar doğrulama ve atomik/idempotent yazma ayrıca gereklidir.

Testler: aynı kod/farklı RecId, boş/tekrarlı kodların ayrılması, tekrarlı görev önleme, yeniden açılınca kalıcılık, eski raporu reddetme, hedefte sonradan oluşan kaydı tespit etme, kanıtsız silmeyi engelleme, bağlam ayrımı ve bozuk kuyrukta durma geçti.

15 Ekim 2026 tarihinde LiveServer açıldıktan sonra 192.168.3.48:5151 API girişi başarılı oldu. API'nin SentezLiveDev2024 / RecId 7 / kod 012018 üzerinde olduğu SELECT ile doğrulandı. CurrentAccountBO şeması 14 tablo döndürüyor; cari kartın bağlı adres, banka, iletişim ve diğer tabloları aktarım tasarımına dahil edilmelidir. api-capabilities.json bu salt okunur keşfi saklar; parola/oturum anahtarı içermez.

PostBO ve UpdateBO kodları incelendi: Sentez iş nesnesini oluşturup PostData üzerinden kaydediyorlar. PostBO'ya pozitif kaynak RecId gönderilmesi farklı işlem yoluna sokabiliyor; kaynak kimliklerinin gelişigüzel aktarılmaması gerekiyor. SQL temel alanları ile API'nin hesaplanan/lookup alanları ayrılmalı; dış referanslar ve detay sahipliği doğrulanmalı. Henüz API yazma çağrısı yapılmadı ve otomatik aktarım devrede değil.

## Banka fişleri — dördüncü sürüm

Banka Fişleri sekmesi şirket 7'nin bütün banka fişlerini UniqueId ile karşılaştırır. Fiş başlığı, hareketler ve ekler ayrı özetlenir. Kaynak/hedef oluşturan kullanıcı adları Meta_User üzerinden ayrı okunur; bu alanlar kayıtların hangi uygulamayla oluşturulduğunu kanıtlamaz. Aynı fiş numarasının farklı UniqueId taşıması, tekrarlı veya eksik UniqueId, eksik banka/muhasebe referansları ayrıca gösterilir.

Okuma 1000 kayıtlık sayfalarla yapılır. Tüm tarama tek bir veritabanı anlık görüntüsü değildir; işlem devam ederken yapılan değişiklikler yeniden kontrol gerektirir. Bağlı kayıt numaraları henüz normalleştirilmediğinden içerik farkı otomatik yazma talimatı değildir. Başlığı aynı olup hareketleri veya ekleri farklı olan fişler de görünür.

Banka ekranı salt okunurdur. Yazma adaptörü, muhasebe belgesi eşleştirmesi ve kalıcı değişiklik/silme takibi tamamlanmadan otomatik aktarım açılmaz. Kaynakta bulunmayan mevcut hedef fişleri silinmez. Kullanıcı hesabı veya işlem günlüğü değiştirilmez.

İlk eşitleme kararı: Kullanıcının seçimiyle başlangıçta yalnız hedefte bulunan 16 banka fişi korunur ve fark olarak gösterilir. profile.json içindeki initialTargetOnlyPolicy=preserve-and-report bu tercihi saklar. Sonradan oluşan kaynak silmeleri ayrı değişiklik takibi ve doğrulanmış eşleştirme gerektirir.

Son gerçek banka kontrolü: kaynak 75.640, hedef 75.604; 75.588 eşit başlık/hareket/ek özeti, 52 yalnız kaynak, 16 yalnız hedef. Eşleşen kayıtlarda oluşturan kullanıcı farkı bulunmadı. Bu bulgu geçmiş kayıtları açıklıyor; gönderilen EXE'nin çalışma anında hangi kullanıcıyı yazdığını kanıtlamıyor.

49.606 eski kayıt her iki tarafta da UniqueId taşımıyor. Bunlar fiş türü + numarası + tarih ile, anahtar tekilliği denetlenerek karşılaştırılıyor. Geçerli UniqueId bulunan kaydın kimliği bu alternatif anahtarla geçersiz kılınmaz. 52 kaynak fişinin 50'sinin muhasebe fişi var ve bu 50 muhasebe fişi hedefte tür/numara/tarih anahtarıyla bulunamadı. Diğer iki kaynak fişi satırsız. Bu nedenle bu sürümde henüz banka aktarımı uygulanmadı.

28 otomatik kontrol geçti; Release derlemesi ve gerçek veri yükleme doğrulandı. Satır değişikliği, boş detay özeti, eski kayıt eşleştirmesi, farklı UniqueId çakışması, mükerrer kimlik ve hedefteki kaydın silinmemesi kontrolleri dahil.

## Banka–muhasebe yazma adaptörü — pilot

Bank-Pilot.ps1 ve Bank-Transfer.ps1, desteklenen tek banka/muhasebe çiftini hazırlayan ve API üzerinden yazan pilot adaptördür. Normal masaüstü Başlat düğmesi bu adaptörü çalıştırmaz. Varsayılan çalışma yalnız önizleme yapar; -Execute yazma modudur. API kullanıcı adı ve parolası standart girişten alınır, dosyaya kaydedilmez.

Ön kontrol: kaynak paket yeniden okunur, şirket ve hedef veritabanı doğrulanır, banka/döviz/muhasebe hesapları kodlarıyla eşleştirilir, tutarlar dengelenir, hedefte mevcut fiş bulunursa durulur. Muhasebe entegrasyon ayarı 2 değilse çift kayıt riskine karşı yazılmaz. Kaynak oluşturma/değiştirme kullanıcı alanları kopyalanmaz; hedef iş nesnesi kendi oturum hesabını kullanır. Kaynak alanları ayrı yerel kaynak paketinde korunur.

İşlem sırası: banka fişi ve hareketi → geri okuma → muhasebe fişi ve satırları → geri okuma → banka/muhasebe bağlantısı → son kontrol. Bunlar ayrı API işlemleridir; tek atomik SQL işlemi değildir. Her aşama transfers altında kalıcı durum dosyasına yazılır. Ağ hatası veya doğrulama hatasında durulur; durum dosyası bulunan kayıt otomatik yeniden gönderilmez. Yarım kalan kayıtlar uzlaştırılmadan tekrar çalıştırılamaz. Bu sürüm henüz genel otomatik aktarım, güncelleme veya silme motoru değildir.

16 Ekim 2026: 00016255 / kaynak RecId 474362 / muhasebe RecId 1545119 için yazmasız güncel ön kontrol başarılı. Tutar 239,99; 1 banka hareketi ve 2 muhasebe satırı. Dokuz adaptör testi hem geliştirme ortamında hem Windows PowerShell ortamında geçti. Gerçek yazma isteği otomatik onay incelemesi tarafından, seçili pilot kayıtlar için açık kullanıcı onayı gerekçesiyle çalıştırılmadan reddedildi. Bu aşamada hedefte kayıt oluşturulmadı.

Pilot yazma sonucu — 16 Ekim 2026: Kullanıcı yalnız 00016255 banka fişi ve bağlı muhasebe fişi aktarımını açıkça onayladı. BankReceiptBO PostBO çağrısı Sentez tarafından “Demo uygulama için kayıt limiti aşıldı.” hatasıyla reddedildi. Sonraki salt okunur sorgu hedef banka ve planlanan muhasebe kaydı için boş sonuç döndürdü. GL PostBO ve bağlantı güncellemesi çağrılmadı. transfers/bank-474362.json hata ve uzlaştırma sonucunu korur. LiveServer demo/lisans sorunu çözülmeden pilot tekrar gönderilmemelidir; mevcut durum dosyası tekrarları engeller. Otomatik aktarım kapalıdır.
