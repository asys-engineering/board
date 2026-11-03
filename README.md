# Board @ ASYS

ASYS Engineering saha takip paneli — şantiye ekibinin eksikleri ve soru işaretlerini tek listede topladığı, haftalık koordinasyon toplantısında çözüldüğü uygulama.

- **Canlı:** https://asys-engineering.github.io/board/
- **Veritabanı:** Supabase (`db/schema.sql`)
- **Barındırma:** GitHub Pages (bu depo, `main` dalı, kök dizin)
- **Telefon:** PWA — tarayıcıda "Ana ekrana ekle"

## Dosyalar
| Dosya | Görev |
|---|---|
| `index.html` | Uygulamanın tamamı (tek dosya) |
| `config.js` | Supabase adresi ve publishable anahtarı (`config.example.js`'ten kopyalanır; depoya GitHub arayüzünden eklenir) |
| `manifest.webmanifest`, `sw.js`, `icon-*.png` | PWA |
| `db/schema.sql` | Tablolar, RLS, `board_*` fonksiyonları |
| `tests/board.test.js` | Playwright testleri (bellek-içi Supabase mock'u) |

## Güvenlik modeli
Tarayıcı yalnızca okur (Supabase publishable anahtarı + RLS; bu anahtar tasarım gereği herkese açıktır). Tüm yazmalar `board_*` SQL fonksiyonları üzerinden, PIN ile alınan oturum token'ı ile yapılır. PM şifresi ve PIN'ler sunucuda bcrypt ile saklanır; depoda hiçbir gizli değer yoktur.

## Güncelleme
`index.html` değişir → `main`'e push → 1 dakika içinde canlı.
