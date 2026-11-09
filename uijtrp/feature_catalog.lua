return {
    {
        name = "Handphone",
        sub = "Buka handphone melalui radial menu",
        icon = "phone",
        items = {
            { title = "Kontak & panggilan", detail = "Kelola kontak dan hubungi pemain", icon = "user" },
            { title = "Pesan pribadi & grup", detail = "SMS dan obrolan grup", icon = "chat" },
            { title = "Kendaraan", detail = "Lihat kendaraan melalui aplikasi", icon = "vehicle" },
            { title = "Layanan darurat", detail = "Hubungi layanan faksi dari handphone", icon = "help" },
            { title = "Yellow Pages & X", detail = "Iklan dan media sosial karakter", icon = "map" }
        }
    },
    {
        name = "Pekerjaan",
        sub = "Pekerjaan dan aktivitas ekonomi gamemode",
        icon = "briefcase",
        items = {
            { title = "Transportasi & pengantaran", detail = "Bus, delivery, hauling, dan kurir", icon = "vehicle" },
            { title = "Panen & produksi", detail = "Petani, penjahit, pemerah susu, dan butcher", icon = "briefcase" },
            { title = "Pengumpulan bahan", detail = "Miner, lumberjack, recycler, dan rongsokan", icon = "briefcase" },
            { title = "Layanan kota", detail = "Sweeper, mowing, forklift, dan trashmaster", icon = "map" },
            { title = "Pekerjaan khusus", detail = "Oilman, electrician, nelayan, dan smugler", icon = "settings" }
        }
    },
    {
        name = "Kota & Ekonomi",
        sub = "Layanan publik, tempat usaha, dan properti",
        icon = "bank",
        items = {
            { title = "Bank & ATM", detail = "Gunakan layanan di lokasi bank atau ATM", icon = "bank" },
            { title = "Rumah & rusun", detail = "Kelola properti melalui titik interaksi", icon = "home" },
            { title = "Bisnis & warung", detail = "Belanja dan layanan usaha di lokasi", icon = "briefcase" },
            { title = "Garasi & rental", detail = "Lihat kendaraan melalui /myv; layanan rental tetap mengikuti titik lokasi", icon = "vehicle", command = "/myv" },
            { title = "Lampu hazard", detail = "Nyalakan atau matikan lampu hazard saat mengemudi", icon = "vehicle", command = "/toghazard" },
            { title = "Workshop & bengkel", detail = "Perbaikan dan layanan kendaraan", icon = "settings" },
            { title = "Pasar & gudang", detail = "Akses pasar, penyimpanan, dan logistik", icon = "inventory" },
            { title = "Peta & interaksi dinamis", detail = "Pintu, gate, tombol, icon map, dan area", icon = "map" },
            { title = "Jalan raya & tol", detail = "Speed camera dan layanan tol sesuai lokasi", icon = "vehicle" }
        }
    },
    {
        name = "Aktivitas Kota",
        sub = "Aktivitas, minigame, dan layanan lain",
        icon = "map",
        items = {
            { title = "Memancing", detail = "Aktivitas nelayan dan perlengkapan sesuai lokasi", icon = "map" },
            { title = "Balapan", detail = "Ikuti UI balapan saat event tersedia", icon = "vehicle" },
            { title = "Universitas", detail = "Akses surat dan layanan universitas", icon = "help" },
            { title = "Gym & kesehatan", detail = "Latihan dan layanan karakter", icon = "health" },
            { title = "Berburu & ladang", detail = "Aktivitas sesuai area dan perlengkapan", icon = "map" },
            { title = "Mesin & minigame", detail = "Slot, billiard, perbaikan, dan uranium", icon = "settings" },
            { title = "Event & perampokan", detail = "UI event dibuka saat syarat server terpenuhi", icon = "help" }
        }
    },
    {
        name = "Personalisasi",
        sub = "Penampilan dan ekspresi karakter",
        icon = "settings",
        items = {
            { title = "Pakaian & aksesori", detail = "Menu pakaian, toys, dan aksesori VIP", icon = "user" },
            { title = "Animasi", detail = "Gunakan /elist untuk melihat animasi", icon = "chat", command = "/elist" },
            { title = "Masker", detail = "Gunakan /mask untuk memakai atau melepas", icon = "settings", command = "/mask" },
            { title = "Toys VIP", detail = "Gunakan /axp untuk membuka menu aksesori", icon = "settings", command = "/axp" },
            { title = "Daftar VIP online", detail = "Lihat pemain VIP yang sedang online", icon = "user", command = "/viplist" }
        }
    },
    {
        name = "Layanan & Faksi",
        sub = "Layanan darurat dan kelompok karakter",
        icon = "user",
        items = {
            { title = "Polisi & EMS", detail = "Buka panduan perintah faksi dengan /fhelp", icon = "help", command = "/fhelp" },
            { title = "Keluarga", detail = "Lihat informasi keluarga melalui /myfam", icon = "user", command = "/myfam" },
            { title = "Bengkel & transportasi", detail = "Layanan mekanik dan transportasi kota", icon = "vehicle" },
            { title = "Pedagang & layanan publik", detail = "Menu pedagang dan layanan sesuai lokasi", icon = "briefcase" },
            { title = "Rumah sakit & hotline", detail = "Panggilan darurat tersedia di aplikasi handphone", icon = "phone" }
        }
    },
    {
        name = "Alat & HUD",
        sub = "HUD, navigasi, radio, dan notifikasi",
        icon = "settings",
        items = {
            { title = "Status karakter", detail = "HUD health/armor; lapar dan haus lewat /stats", icon = "health", command = "/stats" },
            { title = "Radial menu", detail = "Tekan M atau gunakan /lradial untuk membuka pintasan aksi", icon = "settings", command = "/lradial" },
            { title = "Radio & voice", detail = "Gunakan perangkat radio dan voice mode server", icon = "chat" },
            { title = "Kompas & notifikasi", detail = "Petunjuk arah, bantuan, dan status aktivitas", icon = "map" }
        }
    }
}
