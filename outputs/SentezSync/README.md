# SentezSync — ilk inceleme aracı

Hedef akış: 192.168.3.48 üzerindeki SentezLiveDev2025 / şirket 7 (012018) → SentezLiveDev2024 / şirket 7. İstenen kapsam şirkete ait tüm iş verilerinin ekleme, güncelleme ve silmeleridir.

## Bu sürüm ne yapıyor?

İki SQL veritabanına bağlanır, şirket kimliğini doğrular, tablo ve kolon yapılarını karşılaştırır, CompanyId ile doğrudan ilişkilendirilmiş ERP tablolarında kayıt sayar ve fiziksel yabancı anahtar ilişkilerini raporlar. CompanyId bulunmayan detay/ortak tabloları ayrıca incelenmek üzere işaretler. Sistem tablolarını otomatik aktarım adayı yapmaz. Şifreyi kaydetmez.

**Bu sürüm otomatik aktarım yapmaz.** Sentez'e yazma adaptörü, kalıcı görev kuyruğu, kayıt eşleştirme ve silme takibi henüz uygulanmamıştır. İki veritabanındaki gerçek yapıyı doğrulamadan genel tablo kopyalama uygulanmamalıdır. Şema eşitliği ve satır sayısı eşitliği, içerik eşitliğini kanıtlamaz. İnceleme sayımları eşzamanlı işlemler altında tutarlı bir anlık görüntü değildir.

## Çalıştırma

Windows PowerShell veya PowerShell 7 üzerinde:

```powershell
# SQL hesabı: kullanıcı/parola yerel pencerede istenir.
.\Inspect-Sentez.ps1 -Authentication Sql

# Windows hesabıyla:
.\Inspect-Sentez.ps1 -Authentication Windows

# Büyük veritabanlarında ilk aşamada satır sayımlarını atlamak için:
.\Inspect-Sentez.ps1 -Authentication Sql -SkipCounts
```

SQL hesabının iki veritabanında SELECT ve gerekli metadata görüntüleme yetkisi olmalıdır. Hesap için bu araç sunucuda yetki oluşturmaz. Betik sadece SELECT sorguları gönderir. Test ortamında TLS kullanılır; sunucu sertifikasının güven zinciri doğrulaması bu yerel test aracında kapalıdır (TrustServerCertificate). Üretimde doğrulanmış sertifika kullanılmalıdır.

Her başarılı çalışma reports altında benzersiz klasör oluşturur:

- inspection.json: şirketler, tablo durumları ve sınırlamalar.
- tables.csv: kaynak/hedef sayımları ve inceleme sınıfları.
- source-schema.csv / target-schema.csv: kolon yapıları.
- source-relations.csv / target-relations.csv: fiziksel ilişkiler.

CompanyScopedCandidate yalnızca ilk teknik adaydır; aktarım onayı değildir. OwnershipReview detay tablolarının atlanacağı anlamına gelmez; şirket sahipliğinin üst kayıt üzerinden çözülmesi gerekir.

## Bağlantı bulgusu — 14 Ekim 2026

Test paylaşımındaki dbcon.ini dosyası SentezLiveDev2024 veritabanını gösterdi. Mevcut Windows kimliğiyle SQL girişi SENTEZ2024\Guest için reddedildi. Önceki projenin 5151 REST API girişi hem kayıtlı şirket hem 2018 koduyla CompanyNotFound döndürdü. Henüz şirket 7 kayıtları sunucudan doğrulanamadı.

## Sonraki uygulama aşamaları

1. İki veritabanının şirket ve şemasını bu araçla doğrula.
2. ERP iş nesneleri ve ortak/detay kayıt sahipliğini çıkar; hedefteki mevcut kayıtları kaynakla eşleştir.
3. Sentez iş akışı/kuyruk mekanizmasının değişiklikleri yakalamasını test et. Doğrudan SQL ile yapılan değişikliklerin de kapsanıp kapsanmayacağını ayrıca doğrula.
4. Kalıcı görev anahtarı ve eşleştirme tablosuyla mükerrer işlem önleme; işlem bağımlılık sırası; hata/yeniden deneme ve hedef çakışma kontrolünü uygula.
5. Yeni kayıt, güncelleme, bağlı kayıt silme, bağlantı kesilmesi ve yeniden başlatma senaryolarını kopya veriler üzerinde doğrula.
6. Başarılı testlerden sonra otomatik aktarımı etkinleştir. Kaynakta bulunmamak tek başına hedef kaydı silme gerekçesi değildir; doğrulanmış silme olayı ve kayıt eşleştirmesi gerekir.

## 15 Ekim 2026 doğrulaması

Kullanıcının onayıyla mevcut SQL hesabı gizli konsol girişinden kullanıldı. Her iki veritabanında RecId 7, şirket kodu 012018 ve şirket adı ADAMO MODA TEKSTİL A.Ş olarak doğrulandı. Kaynak ve hedefte 488 tablo için incelenen kolon yapıları eşleşti. 127 doğrudan şirket kapsamlı ERP tablosu, 210 şirket sahipliği ayrıca incelenecek ERP tablosu, 151 sistem/diğer tablo bulundu. API girişi doğru şirket koduyla henüz yeniden test edilmedi.

