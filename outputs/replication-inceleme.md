# Sentez ReplicationServer incelemesi ve yerel deneme tasarımı

Tarih: 14 Ekim 2026
İncelenen dosya: Kullanıcının gönderdiği ReplicationServer.exe
SHA256: DB6071265C6C066B421E4771462248FD5E1783D824F5BBDC4B22F67CDA0A8E51
Yöntem: EXE çalıştırılmadan paket içindeki üç .NET bileşeninin çıkarılması ve ILSpy ile statik kod incelemesi. Canlı veya test veritabanına bağlanılmadı. Aşağıdaki kod konumları work klasöründeki inceleme çıktılarının satırlarıdır; orijinal kaynak kod satırları değildir. Bazı dış bağımlılıklar çözülmediğinden bu çalışma bütün davranışların çalışma zamanı doğrulaması değildir.

## Doğrulanan yapı

- Paket .NET 6.0.36 çalışma ortamlarını içeriyor; ana uygulama WPF.
- Replikasyon istemcisi WCF NetTcpBinding, sunucu CoreWCF kullanıyor. Adres biçimi net.tcp://adres:port/IReplicationServer. Varsayılan port 1347. Önceki sentez-rapor projesindeki 5151 REST API adresi ayrı bir servistir.
- Bağlantı alanları: nokta adı, adres, port, nokta tipi, aktif/pasif mod, kullanıcı kodu/parolası, şirket kodu/parolası, cari/depo/departman kodları, alış/satış fiyat listesi.
- Replikasyon ayarları aktif Sentez oturumunun parametre servisi üzerinden veritabanı bağlantısıyla yükleniyor/kaydediliyor. Uzak noktalar, hedefler ve takvimler XML biçiminde parametre değerlerine dönüştürülüyor. Ayrı appsettings dosyasının bulunmaması tek başına eksik kurulum kanıtı değil.
- Sunucu aktif Sentez veritabanı bağlantısını kullanıyor. ReplicationEnabled ayarı servis başlangıcını etkiliyor.
- İşlem türleri Insert, Update, Delete ve BulkUpdate. Yönler OneWay, OneWayToMaster ve TwoWay; modlar ActiveReplication ve PassiveReplication.
- Kuyruk tabloları Rpl_Task, Rpl_TaskItem ve Rpl_TaskTarget. Kayıtlar iş nesnesi, tablo, kayıt kimliği, veri, görev/hedef anahtarları ve durum bilgilerini içeriyor.
- Rpl_Xref kaynak nokta ve kaynak kayıt kimliğini hedef kayıt kimliğiyle eşleştiriyor. Bazı aktarım yollarında UniqueId kontrolü de var. Bu nedenle iki veritabanındaki aynı RecId değerinin aynı kaydı temsil ettiği varsayılamaz.
- Sentez iş nesneleri, PostData, transaction ve eşleştirme servisleri kullanılıyor. Bütün aktarım yalnızca genel SQL INSERT/UPDATE işlemlerinden oluşmuyor.
- Verilerde sıkıştırma, görev durumu bildirimi, tekrar deneme sayacı ve işlem kuyruğu iş parçacıkları bulunuyor. Tam çakışma çözüm politikası henüz doğrulanmadı.

## Çalıştırmayla ilgili somut bulgular

- MainWindow.Window_Loaded aynı isimli birden fazla işlem görürse uygulamayı kapatıyor. Orijinal EXE'nin iki kopyasını aynı bilgisayarda doğrudan açmak yerel çift düğüm denemesi için uygun değil.
- Başlangıçta CheckRplUser, Replication isimli Sentez kullanıcı kaydını oluşturma/güncelleme yoluna giriyor.
- Başlangıçta Replication tablosundaki LogTime değeri 10 günden eski satırlar için DELETE çalıştırılıyor.
- Stop argümanı etkin değilse ana pencere yüklenirken görev yöneticisini başlatan yol çalışıyor. Argümanın komut satırında tam yazımı bu incelemede doğrulanmadı.
- Hata günlüğü ayarında ReplicationError dosya adı ve tarih ekleme seçeneği bulunuyor; gerçek çıktı klasörü henüz doğrulanmadı.
- Bu bulgular kullanıcının daha önce yaşadığı açılmama hatasının kesin teşhisi değildir.

## Yeni uygulama için önerilen yerel düzen

Tek yönetim uygulaması içinde iki bağımsız düğüm profili:

Kaynak düğüm A -> kalıcı görev kuyruğu -> hedef düğüm B -> işlem sonucu

Her profil kendi Sentez test veritabanını, şirketini ve bağlantısını taşır. Uzak sunucuya geçişte profil adresi ve bağlantı katmanı değişir; eşleştirme ve görev mantığı aynı kalır. Yeni uygulama, orijinal EXE'nin tek işlem kontrolüne bağlı olmayacaktır.

İlk aşama önerisi: tek yönlü stok kartı/fiyat aktarımı. Bu veri kapsamı henüz kullanıcı tarafından kesin seçilmedi. Bağlantı testi, kaynak/hedef kimlik doğrulaması, aktarım önizlemesi, kalıcı kaynak-hedef eşleştirmesi, mükerrer işlem önleme, hata ve tekrar deneme kaydı birlikte hazırlanmalı. Silme ve iki yönlü çakışma çözümü ayrı aşamada ele alınmalı.

Sentez-rapor içindeki doğrulanmış okuma/giriş yöntemleri tekrar kullanılabilir. Swagger'da UpdateBO bulunması tek başına tüm iş nesnelerini doğru yazabildiğimizi kanıtlamaz; gerçek alanlar ve PostData davranışı seçilen test verisiyle doğrulanmalıdır. Yeni uygulamanın orijinal NetTCP protokolüyle birebir uyumlu olduğu iddia edilmemektedir.

## Kod kanıtları

- LiveCore.Replication.cs:625 — ReplicationNodeDefinition ve bağlantı alanları; varsayılan port.
- LiveCore.Replication.cs:1372 — NetTCP uç noktası.
- LiveCore.Replication.cs:1387 — Login parametreleri.
- LiveCore.Replication.cs:1847 — aktif veritabanı bağlantısı.
- LiveCore.Replication.cs:1936 — sunucu portu ve CoreWCF servisi.
- LiveCore.Replication.cs:2972 — PortNumber parametresi, DefaultValue(1347).
- LiveCore.Replication.cs:4632 — şirket bağlamında parametre yükleme.
- LiveCore.Replication.cs:4781 — parametre kaydetme.
- LiveCore.Replication.cs:5117 — Rpl_Xref kaydı oluşturma.
- LiveCore.Replication.cs:7557 — iş nesnesinin transaction ile PostData çağrısı.
- LiveCore.Replication.cs:15517 — değişiklik türleri ve yönler.
- LiveCore.Replication.cs:16974 — görev tabloları.
- ReplicationServer.cs:261 — açılış, ikinci işlem kontrolü, kullanıcı hazırlığı, eski log temizliği ve görev başlatma.
- ReplicationServer.cs:310 — replikasyon kullanıcısı hazırlığı.
