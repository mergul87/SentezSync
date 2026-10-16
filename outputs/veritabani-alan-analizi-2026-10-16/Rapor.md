# Veritabanı alan incelemesi — 16 Ekim 2026

Sunucu: 192.168.3.48. Kapsam: şirket 7 ile sınırlı değil, iki veritabanındaki bütün şirketler ve sistem tabloları. Salt okunur sistem görünümü sorguları kullanıldı. Satır sayıları SQL bölüm istatistiklerinden gelir. Ölçümler farklı anlarda alınmıştır.

| Veritabanı | Veri dosyası (MiB) | Kullanılan (MiB) | Dosya içi boş (MiB) | Log dosyası (MiB) |
|---|---:|---:|---:|---:|
| SentezLiveDev2024 | 30010,81 | 24978,44 | 5032,38 | 1 |
| SentezLiveDev2025 | 30010,81 | 27134,31 | 2876,50 | 1 |

En büyük tablo alanları (veri + indeks; MiB):

| Tablo | 2024 | 2025 |
|---|---:|---:|
| Erp_EInvoice | 9681,37 | 9694,76 |
| Log_Transaction | 5391,94 | 8186,43 |
| Erp_InventoryReceiptItem | 1898,19 | 2175,34 |
| Erp_GLReceiptItem | 1302,24 | 1521,32 |
| Meta_WindowSetting | 834,27 | 834,57 |

Erp_EInvoice alanının yaklaşık tamamı LOB sayfalarındadır. Bu ölçüm saklanan büyük alanların hacmini gösterir; içeriklerinin XML/PDF/resim dağılımı ayrıca ölçülmedi. Log_Transaction, SQL .ldf işlem günlüğünden farklı olan uygulama geçmişi tablosudur.

İki veri dosyasında toplam 7908,88 MiB (yaklaşık 7,72 GiB) ayrılmış ama kullanılmayan alan vardır. Bunun tamamının dosya küçültmeyle geri alınabileceği garanti edilmez. Boş alan gelecekteki büyümede yeniden kullanılabilir.

İzlenecek sıra: e-fatura büyük alanlarının kolon bazında dağılımı; Log_Transaction kayıtlarının tarih ve şirket bazında dağılımı; gerekli saklama süresi ve geri dönüşü test edilmiş arşivleme planı. Henüz hiçbir kayıt silinmedi, indeks kaldırılmadı, dosya küçültülmedi veya kurtarma modeli değiştirilmedi.
