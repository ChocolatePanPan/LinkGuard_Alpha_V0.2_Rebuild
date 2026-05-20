package com.linkguard.app.data

import com.linkguard.app.model.Hospital
import com.linkguard.app.model.HospitalLevel

// =====================================================
//  HospitalData — 靜態醫院目錄資料
//  對齊 iOS FieldHospitalView 的資料結構與分區邏輯
//  全台主要區域醫院 / 地區醫院 / 救援資源中心
// =====================================================

object HospitalData {

    val all: List<Hospital> = listOf(
        // === 台北市 ===
        Hospital(id = "h001", name = "台大醫院", address = "台北市中正區中山南路7號", phone = "02-2312-3456",
            level = HospitalLevel.REGIONAL, city = "台北市", region = "北部",
            icuBeds = 120, orRooms = 30, totalBeds = 2400),
        Hospital(id = "h002", name = "台北榮民總醫院", address = "台北市北投區石牌路二段201號", phone = "02-2871-2121",
            level = HospitalLevel.REGIONAL, city = "台北市", region = "北部",
            icuBeds = 110, orRooms = 28, totalBeds = 2900),
        Hospital(id = "h003", name = "台北市立聯合醫院（仁愛院區）", address = "台北市大安區仁愛路四段10號", phone = "02-2709-3600",
            level = HospitalLevel.DISTRICT, city = "台北市", region = "北部",
            icuBeds = 30, orRooms = 8, totalBeds = 580),
        Hospital(id = "h004", name = "三軍總醫院", address = "台北市內湖區成功路二段325號", phone = "02-8792-7500",
            level = HospitalLevel.REGIONAL, city = "台北市", region = "北部",
            icuBeds = 80, orRooms = 20, totalBeds = 1600),
        Hospital(id = "h005", name = "國泰綜合醫院", address = "台北市大安區仁愛路四段280號", phone = "02-2708-2121",
            level = HospitalLevel.REGIONAL, city = "台北市", region = "北部",
            icuBeds = 50, orRooms = 16, totalBeds = 1000),

        // === 新北市 ===
        Hospital(id = "h010", name = "亞東紀念醫院", address = "新北市板橋區南雅南路二段21號", phone = "02-8966-7000",
            level = HospitalLevel.REGIONAL, city = "新北市", region = "北部",
            icuBeds = 60, orRooms = 18, totalBeds = 900),
        Hospital(id = "h011", name = "新北市立聯合醫院", address = "新北市三重區新北大道一段1號", phone = "02-2982-4545",
            level = HospitalLevel.DISTRICT, city = "新北市", region = "北部",
            icuBeds = 20, orRooms = 6, totalBeds = 400),

        // === 桃園市 ===
        Hospital(id = "h020", name = "林口長庚紀念醫院", address = "桃園市龜山區復興街5號", phone = "03-328-1200",
            level = HospitalLevel.REGIONAL, city = "桃園市", region = "北部",
            icuBeds = 200, orRooms = 50, totalBeds = 3800),
        Hospital(id = "h021", name = "桃園醫院", address = "桃園市桃園區中山路1492號", phone = "03-369-9721",
            level = HospitalLevel.DISTRICT, city = "桃園市", region = "北部",
            icuBeds = 25, orRooms = 7, totalBeds = 500),

        // === 台中市 ===
        Hospital(id = "h030", name = "台中榮民總醫院", address = "台中市西屯區台灣大道四段1650號", phone = "04-2359-2525",
            level = HospitalLevel.REGIONAL, city = "台中市", region = "中部",
            icuBeds = 100, orRooms = 25, totalBeds = 1500),
        Hospital(id = "h031", name = "中國醫藥大學附設醫院", address = "台中市北區育德路2號", phone = "04-2205-2121",
            level = HospitalLevel.REGIONAL, city = "台中市", region = "中部",
            icuBeds = 80, orRooms = 22, totalBeds = 2000),
        Hospital(id = "h032", name = "台中市立烏日林新醫院", address = "台中市烏日區中山路一段98號", phone = "04-2338-0220",
            level = HospitalLevel.DISTRICT, city = "台中市", region = "中部",
            icuBeds = 15, orRooms = 5, totalBeds = 300),

        // === 台南市 ===
        Hospital(id = "h040", name = "成大醫院", address = "台南市北區勝利路138號", phone = "06-235-3535",
            level = HospitalLevel.REGIONAL, city = "台南市", region = "南部",
            icuBeds = 90, orRooms = 24, totalBeds = 1300),
        Hospital(id = "h041", name = "奇美醫院（台南）", address = "台南市永康區中華路901號", phone = "06-281-2811",
            level = HospitalLevel.REGIONAL, city = "台南市", region = "南部",
            icuBeds = 70, orRooms = 20, totalBeds = 1200),

        // === 高雄市 ===
        Hospital(id = "h050", name = "高雄榮民總醫院", address = "高雄市左營區大中一路386號", phone = "07-342-2121",
            level = HospitalLevel.REGIONAL, city = "高雄市", region = "南部",
            icuBeds = 80, orRooms = 20, totalBeds = 1400),
        Hospital(id = "h051", name = "高雄醫學大學附設中和紀念醫院", address = "高雄市三民區十全一路100號", phone = "07-312-1101",
            level = HospitalLevel.REGIONAL, city = "高雄市", region = "南部",
            icuBeds = 70, orRooms = 18, totalBeds = 1300),
        Hospital(id = "h052", name = "高雄市立大同醫院", address = "高雄市前金區中華三路68號", phone = "07-291-1101",
            level = HospitalLevel.DISTRICT, city = "高雄市", region = "南部",
            icuBeds = 20, orRooms = 6, totalBeds = 400),

        // === 宜蘭縣 ===
        Hospital(id = "h060", name = "羅東博愛醫院", address = "宜蘭縣羅東鎮南昌街83號", phone = "03-954-3131",
            level = HospitalLevel.DISTRICT, city = "宜蘭縣", region = "東部",
            icuBeds = 20, orRooms = 6, totalBeds = 450),

        // === 花蓮縣 ===
        Hospital(id = "h070", name = "花蓮慈濟醫院", address = "花蓮市中央路三段707號", phone = "03-856-1825",
            level = HospitalLevel.REGIONAL, city = "花蓮縣", region = "東部",
            icuBeds = 40, orRooms = 12, totalBeds = 1000),

        // === 台東縣 ===
        Hospital(id = "h080", name = "馬偕紀念醫院台東分院", address = "台東市長沙街303巷1號", phone = "089-310150",
            level = HospitalLevel.DISTRICT, city = "台東縣", region = "東部",
            icuBeds = 10, orRooms = 4, totalBeds = 250),

        // === 救援中心 / 消防 ===
        Hospital(id = "r001", name = "內政部消防署", address = "台北市大同區塔城街99號", phone = "119",
            level = HospitalLevel.FIRE, city = "台北市", region = "北部"),
        Hospital(id = "r002", name = "高雄市消防局", address = "高雄市三民區民族一路276號", phone = "07-311-1119",
            level = HospitalLevel.FIRE, city = "高雄市", region = "南部"),
        Hospital(id = "r003", name = "行政院國家搜救指揮中心", address = "台北市中正區重慶南路一段2號", phone = "02-8912-5566",
            level = HospitalLevel.RESCUE_CENTER, city = "台北市", region = "北部")
    )

    val regions: List<String> get() = all.map { it.region }.distinct().sorted()

    fun byRegion(region: String): List<Hospital> = all.filter { it.region == region }

    fun byCity(city: String): List<Hospital> = all.filter { it.city == city }

    fun search(query: String): List<Hospital> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return all
        return all.filter {
            it.name.lowercase().contains(q) ||
            it.city.lowercase().contains(q) ||
            it.address.lowercase().contains(q)
        }
    }

    /** 根據城市名稱猜測所在地區（用於 GPS 反查後縮小範圍） */
    fun regionForCity(city: String): String? =
        all.firstOrNull { it.city == city }?.region

    val cities: List<String> get() = all.map { it.city }.distinct().sorted()
}
