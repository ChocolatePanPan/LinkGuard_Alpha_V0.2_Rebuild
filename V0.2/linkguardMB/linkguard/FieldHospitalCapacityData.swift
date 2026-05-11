import Foundation

/// 前線醫療量能資料（南投縣 10 筆、新竹市 9 筆；原始 CSV 為 UTF-8）
struct FieldHospitalCapacityMetric: Hashable {
    let label: String
    let count: Int
}

struct FieldHospitalCapacity: Identifiable, Hashable {
    enum SourceKind: String, Hashable {
        case licensedBeds = "許可床數"
        case serviceCapacity = "醫療量能"

        var label: String { L(rawValue) }
    }

    let id: String
    let sourceKind: SourceKind
    let region: FieldHospital.Region
    let city: String
    let agency: String
    let name: String
    let metrics: [FieldHospitalCapacityMetric]

    var nonZeroMetrics: [FieldHospitalCapacityMetric] {
        metrics.filter { $0.count > 0 }
    }

    var totalCount: Int {
        metrics.reduce(0) { $0 + $1.count }
    }

    var searchableText: String {
        ([agency, name, city, sourceKind.rawValue] + metrics.map(\.label) + metrics.map { String($0.count) })
            .joined(separator: " ")
    }

    var mapsURL: URL? {
        let query = [city, name].filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

enum FieldHospitalCapacityDirectory {
    static let all: [FieldHospitalCapacity] = [
        .init(id: "HC001", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "衛生福利部南投醫院", metrics: [.init(label: "急性一般病床", count: 290), .init(label: "精神急性病床", count: 44), .init(label: "慢性一般病床", count: 130), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC002", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "彰化基督教醫療財團法人南投基督教醫院", metrics: [.init(label: "急性一般病床", count: 150), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC003", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "衛生福利部草屯療養院", metrics: [.init(label: "急性一般病床", count: 0), .init(label: "精神急性病床", count: 193), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 800)]),
        .init(id: "HC004", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "曾漢棋綜合醫院", metrics: [.init(label: "急性一般病床", count: 56), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC005", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "佑民醫療社團法人佑民醫院", metrics: [.init(label: "急性一般病床", count: 282), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC006", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "惠和醫院", metrics: [.init(label: "急性一般病床", count: 20), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC007", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "埔基醫療財團法人埔里基督教醫院", metrics: [.init(label: "急性一般病床", count: 268), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 100), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC008", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "臺中榮民總醫院埔里分院", metrics: [.init(label: "急性一般病床", count: 152), .init(label: "精神急性病床", count: 23), .init(label: "慢性一般病床", count: 550), .init(label: "精神慢性病床", count: 50)]),
        .init(id: "HC009", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "東華醫院", metrics: [.init(label: "急性一般病床", count: 73), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC010", sourceKind: .licensedBeds, region: .central, city: "南投縣", agency: "南投縣政府", name: "竹山秀傳醫療社團法人竹山秀傳醫院", metrics: [.init(label: "急性一般病床", count: 227), .init(label: "精神急性病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "精神慢性病床", count: 0)]),
        .init(id: "HC011", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "國立臺灣大學醫學院附設醫院新竹臺大分院新竹醫院", metrics: [.init(label: "急性一般病床", count: 536), .init(label: "急性精神病床", count: 36), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 6), .init(label: "加護病房", count: 49), .init(label: "亞急性呼吸照護", count: 12), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 30), .init(label: "手術恢復床", count: 6), .init(label: "嬰兒床", count: 16), .init(label: "嬰兒病床", count: 13), .init(label: "血液透析病床", count: 70), .init(label: "燒傷加護病床", count: 4), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 7), .init(label: "手術台", count: 13), .init(label: "產台", count: 2), .init(label: "門診治療室", count: 54), .init(label: "牙科治療室", count: 16), .init(label: "精神科日照單位", count: 100), .init(label: "牙醫治療台", count: 0)]),
        .init(id: "HC012", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "平和醫療社團法人和平醫院", metrics: [.init(label: "急性一般病床", count: 0), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 50), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 0), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 27), .init(label: "急性觀察床", count: 0), .init(label: "手術恢復床", count: 0), .init(label: "嬰兒床", count: 0), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 0), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 0), .init(label: "手術台", count: 0), .init(label: "產台", count: 0), .init(label: "門診治療室", count: 2), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 0)]),
        .init(id: "HC013", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "新中興醫院", metrics: [.init(label: "急性一般病床", count: 20), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 0), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 16), .init(label: "急性觀察床", count: 0), .init(label: "手術恢復床", count: 0), .init(label: "嬰兒床", count: 0), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 0), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 0), .init(label: "手術台", count: 0), .init(label: "產台", count: 0), .init(label: "門診治療室", count: 6), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 5)]),
        .init(id: "HC014", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "財團法人台灣省私立桃園仁愛之家附設新竹新生醫院", metrics: [.init(label: "急性一般病床", count: 40), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 0), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 20), .init(label: "急性觀察床", count: 0), .init(label: "手術恢復床", count: 0), .init(label: "嬰兒床", count: 0), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 0), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 0), .init(label: "手術台", count: 0), .init(label: "產台", count: 0), .init(label: "門診治療室", count: 2), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 0)]),
        .init(id: "HC015", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "國軍桃園總醫院新竹分院附設民眾診療服務處", metrics: [.init(label: "急性一般病床", count: 101), .init(label: "急性精神病床", count: 67), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 8), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 12), .init(label: "手術恢復床", count: 3), .init(label: "嬰兒床", count: 15), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 20), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 2), .init(label: "手術台", count: 4), .init(label: "產台", count: 2), .init(label: "門診治療室", count: 18), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 5)]),
        .init(id: "HC016", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "國泰醫療財團法人新竹國泰綜合醫院", metrics: [.init(label: "急性一般病床", count: 217), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 16), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 37), .init(label: "手術恢復床", count: 8), .init(label: "嬰兒床", count: 20), .init(label: "嬰兒病床", count: 17), .init(label: "血液透析病床", count: 30), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 0), .init(label: "負壓隔離病床", count: 0), .init(label: "手術台", count: 7), .init(label: "產台", count: 2), .init(label: "門診治療室", count: 22), .init(label: "牙科治療室", count: 5), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 0)]),
        .init(id: "HC017", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "台灣基督長老教會馬偕醫療財團法人新竹馬偕紀念醫院", metrics: [.init(label: "急性一般病床", count: 353), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 32), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 30), .init(label: "手術恢復床", count: 10), .init(label: "嬰兒床", count: 0), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 68), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 1), .init(label: "負壓隔離病床", count: 3), .init(label: "手術台", count: 15), .init(label: "產台", count: 0), .init(label: "門診治療室", count: 48), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 20), .init(label: "牙醫治療台", count: 14)]),
        .init(id: "HC018", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "新竹市立馬偕兒童醫院(委託台灣基督長老教會馬偕醫療財團法人興建經營)", metrics: [.init(label: "急性一般病床", count: 143), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 14), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 18), .init(label: "手術恢復床", count: 4), .init(label: "嬰兒床", count: 30), .init(label: "嬰兒病床", count: 24), .init(label: "血液透析病床", count: 0), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 2), .init(label: "負壓隔離病床", count: 2), .init(label: "手術台", count: 7), .init(label: "產台", count: 2), .init(label: "門診治療室", count: 32), .init(label: "牙科治療室", count: 0), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 5)]),
        .init(id: "HC019", sourceKind: .serviceCapacity, region: .north, city: "新竹市", agency: "新竹市", name: "南門綜合醫院", metrics: [.init(label: "急性一般病床", count: 73), .init(label: "急性精神病床", count: 0), .init(label: "慢性一般病床", count: 0), .init(label: "安寧病床", count: 0), .init(label: "加護病房", count: 10), .init(label: "亞急性呼吸照護", count: 0), .init(label: "慢性呼吸照護", count: 0), .init(label: "急性觀察床", count: 6), .init(label: "手術恢復床", count: 3), .init(label: "嬰兒床", count: 0), .init(label: "嬰兒病床", count: 0), .init(label: "血液透析病床", count: 15), .init(label: "燒傷加護病床", count: 0), .init(label: "普通隔離病床", count: 2), .init(label: "負壓隔離病床", count: 0), .init(label: "手術台", count: 3), .init(label: "產台", count: 0), .init(label: "門診治療室", count: 16), .init(label: "牙科治療室", count: 6), .init(label: "精神科日照單位", count: 0), .init(label: "牙醫治療台", count: 0)]),
    ]

    static func cities(region: FieldHospital.Region?) -> [String] {
        let source = all.filter { region == nil || $0.region == region }
        return Array(Set(source.map(\.city))).sorted()
    }

    static func grouped() -> [(region: FieldHospital.Region, items: [FieldHospitalCapacity])] {
        FieldHospital.Region.allCases.compactMap { region in
            let items = all.filter { $0.region == region }
            return items.isEmpty ? nil : (region, items)
        }
    }
}