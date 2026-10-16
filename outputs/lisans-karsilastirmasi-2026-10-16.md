# Lisans karşılaştırması — 16 Ekim 2026

192.168.3.48 üzerindeki eski, SentezLiveDev2024 ve SentezLiveDev2025 veritabanları salt okunur incelendi.

- Üçünde de License_Activation ve License_ActiveUser tabloları mevcut.
- License_Activation tablosunda her veritabanında iki kayıt var (LicenseType 0 ve 1). Sayısal türlerin ürün içindeki anlamı bu incelemede doğrulanmadı.
- Tür 0 kayıtlarının veri ve doğrulama özetleri eşit.
- Tür 1 lisans kodlarının SHA-256 özetleri eşit. Aktivasyon verisi ve doğrulama özetleri eski veritabanına göre iki yeni veritabanında farklı.
- Bu karşılaştırma lisansın silindiğini göstermiyor. Lisansın hangi kuruluma bağlı olduğunu veya hangi aktivasyonun geçerli olduğunu da tek başına kanıtlamıyor.
- Şirket 7 kodu üçünde de 012018. Eski şirket unvanı uzun yazımlı; yeni veritabanlarında kısaltılmış. Bunun lisans doğrulamasını etkileyip etkilemediği bilinmiyor.
- Lisans kodu, aktivasyon içeriği veya doğrulama değeri dışarı aktarılmadı. Hiçbir lisans kaydı kopyalanmadı veya değiştirilmedi.

Sonraki ayırıcı kontrol: aynı Sentez kurulumu eski veritabanıyla açıldığında da demo hatası veriyor mu? Eski yedeğin varlığı, lisansın şu anda geçerli olduğunu kanıtlamaz. Gerekirse mevcut lisansın ürünün normal aktivasyon süreciyle doğrulanması gerekir.

Ek teşhis: Sentez'in kendi salt okunur ayrıştırıcısıyla üç veritabanındaki lisans bilgileri kontrol edildi. Üçünde de IsEnabled=true, IsActivated=true, ProductVersion=1.0.5718.33522, Period=0. Bu alanlar lisans kaydındaki durumu gösterir; çalışan sunucunun lisansı kabul ettiğini tek başına kanıtlamaz. Geçici şifreli teşhis girdisi inceleme sonrasında silindi.

LiveServer ürün sürümü 1.0.0.0. ProgramParameters lisans sunucusu ayarı SentezServerIP=192.168.3.50, SentezServerPort=4000. İncelenen ürün kodunda lisans WebSocket bağlantısı kurulamaması demo durumuna neden olabiliyor. Bu bilgisayardan 192.168.3.50:4000 ve 192.168.3.48:4000 TCP bağlantıları başarısız. Bu ölçüm 192.168.3.48 sunucusundan yapılan bir bağlantı testi değildir.

Windows hizmet yöneticisi 192.168.3.48 üzerindeki SWService hizmetini STOPPED olarak bildirdi. Bağlantı hedefi 192.168.3.50 olduğu için yalnız test sunucusundaki durmuş hizmet, tek başına kesin kök neden değildir; servis konumu doğrulanmalıdır.
