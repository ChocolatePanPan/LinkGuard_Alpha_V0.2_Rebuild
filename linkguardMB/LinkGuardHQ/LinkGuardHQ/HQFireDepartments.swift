import Foundation

/// 全臺消防局聯絡資料
/// 資料來源：各縣市消防局公開總局所在地
struct HQFireDepartment: Identifiable, Hashable {
    enum Region: String, CaseIterable {
        case north    = "北部"
        case northeast = "東北"
        case central  = "中部"
        case south    = "南部"
        case east     = "東部"
        case offshore = "離島"
    }

    let id: String        // 用縣市名稱當 id
    let region: Region
    let city: String      // 縣市
    let name: String      // 消防局名稱
    let address: String   // 總局所在地

    var phone: String { "119" }   // 全臺消防局統一報案電話
}

enum HQFireDepartmentDirectory {
    static let all: [HQFireDepartment] = [
        // 北部
        .init(id: "基隆市", region: .north, city: "基隆市", name: "基隆市消防局",     address: "基隆市安樂區基金一路129巷6號"),
        .init(id: "臺北市", region: .north, city: "臺北市", name: "臺北市政府消防局", address: "臺北市信義區松仁路1號"),
        .init(id: "新北市", region: .north, city: "新北市", name: "新北市政府消防局", address: "新北市板橋區南雅南路二段15號"),
        .init(id: "桃園市", region: .north, city: "桃園市", name: "桃園市政府消防局", address: "桃園市桃園區力行路280號"),
        .init(id: "新竹市", region: .north, city: "新竹市", name: "新竹市消防局",     address: "新竹市西大路679號"),
        .init(id: "新竹縣", region: .north, city: "新竹縣", name: "新竹縣政府消防局", address: "新竹縣竹北市光明五街295號"),
        // 東北
        .init(id: "宜蘭縣", region: .northeast, city: "宜蘭縣", name: "宜蘭縣政府消防局", address: "宜蘭市舊城南路1號"),
        // 中部
        .init(id: "苗栗縣", region: .central, city: "苗栗縣", name: "苗栗縣政府消防局", address: "苗栗市經國路4段201號"),
        .init(id: "臺中市", region: .central, city: "臺中市", name: "臺中市政府消防局", address: "臺中市南屯區文心南九路119號"),
        .init(id: "彰化縣", region: .central, city: "彰化縣", name: "彰化縣消防局",     address: "彰化市中央路1號"),
        .init(id: "南投縣", region: .central, city: "南投縣", name: "南投縣政府消防局", address: "南投市民族路494號"),
        .init(id: "雲林縣", region: .central, city: "雲林縣", name: "雲林縣消防局",     address: "雲林縣斗六市公園路6號"),
        // 南部
        .init(id: "嘉義市", region: .south, city: "嘉義市", name: "嘉義市政府消防局", address: "嘉義市立學街16號"),
        .init(id: "嘉義縣", region: .south, city: "嘉義縣", name: "嘉義縣消防局",     address: "嘉義縣太保市祥和二路東段6號"),
        .init(id: "臺南市", region: .south, city: "臺南市", name: "臺南市政府消防局", address: "臺南市安平區永華路二段898號"),
        .init(id: "高雄市", region: .south, city: "高雄市", name: "高雄市政府消防局", address: "高雄市前鎮區凱旋四路119號"),
        .init(id: "屏東縣", region: .south, city: "屏東縣", name: "屏東縣政府消防局", address: "屏東市忠孝路226號"),
        // 東部
        .init(id: "花蓮縣", region: .east, city: "花蓮縣", name: "花蓮縣消防局",     address: "花蓮縣花蓮市中央路三段842號"),
        .init(id: "臺東縣", region: .east, city: "臺東縣", name: "臺東縣消防局",     address: "臺東市四維路二段100號"),
        // 離島
        .init(id: "澎湖縣", region: .offshore, city: "澎湖縣", name: "澎湖縣政府消防局", address: "澎湖縣馬公市四維路320號"),
        .init(id: "金門縣", region: .offshore, city: "金門縣", name: "金門縣消防局",     address: "金門縣金寧鄉頂林路315號"),
        .init(id: "連江縣", region: .offshore, city: "連江縣", name: "連江縣消防局",     address: "連江縣南竿鄉清水村84之1號"),
    ]

    /// 依區域分組
    static func grouped() -> [(region: HQFireDepartment.Region, items: [HQFireDepartment])] {
        HQFireDepartment.Region.allCases.map { region in
            (region, all.filter { $0.region == region })
        }
    }

    /// 依縣市名稱查找（可從受困者地址推導）
    static func find(byCity city: String) -> HQFireDepartment? {
        all.first { city.contains($0.city) || $0.city.contains(city) }
    }
}
