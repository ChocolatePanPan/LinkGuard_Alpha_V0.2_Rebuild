import SwiftUI

/// iOS Field 急診醫院資料（185 家，資料源：衛福部醫院清單 2024-12-31）
struct FieldHospital: Identifiable, Hashable {
    enum Region: String, CaseIterable {
        case north       = "北部"
        case central     = "中部"
        case yunjianan   = "雲嘉南"
        case gaopingpeng = "高屏澎"
        case east        = "東部"
        case offshore    = "離島"

        var label: String { L(rawValue) }
    }
    enum Level: String, CaseIterable {
        case heavy    = "重度／教學"
        case moderate = "中度"
        case children = "兒童／婦兒"
        case unknown  = "待查"

        var label: String { L(rawValue) }

        var icon: String {
            switch self {
            case .heavy:    return "cross.circle.fill"
            case .moderate: return "cross.circle"
            case .children: return "figure.child"
            case .unknown:  return "questionmark.circle"
            }
        }
        var color: Color {
            switch self {
            case .heavy:    return .red
            case .moderate: return .orange
            case .children: return .purple
            case .unknown:  return .secondary
            }
        }
    }
    let id: String
    let region: Region
    let city: String
    let name: String
    let level: Level
    let purpose: String
    let phone: String
    let address: String
    /// 病床總計（逐院或所在行政區，2024-12-31）
    let totalBeds: Int
    /// 加護病床數（所在行政區）
    let icuBeds: Int
    /// 急診觀察床數（所在行政區）
    let erBeds: Int
}

enum FieldHospitalDirectory {
    static let all: [FieldHospital] = [
        .init(id:"ER001",region:.north,city:"基隆市",name:"衛生福利部基隆醫院",level:.moderate,purpose:"",phone:"0224292525",address:"基隆市信義區信二路２６８號",totalBeds:459,icuBeds:30,erBeds:12),
        .init(id:"ER002",region:.north,city:"基隆市",name:"基隆長庚紀念醫院",level:.moderate,purpose:"",phone:"0224313131",address:"基隆市安樂區麥金路222號(行政院區麥金路201號)",totalBeds:1324,icuBeds:63,erBeds:30),
        .init(id:"ER003",region:.north,city:"基隆市",name:"臺灣礦工醫院",level:.moderate,purpose:"",phone:"0224579101",address:"基隆市暖暖區源遠路２９號",totalBeds:130,icuBeds:6,erBeds:6),
        .init(id:"ER004",region:.north,city:"臺北市",name:"馬偕紀念醫院",level:.moderate,purpose:"",phone:"0225433535",address:"臺北市中山區中山北路二段９２號",totalBeds:776,icuBeds:100,erBeds:39),
        .init(id:"ER005",region:.north,city:"臺北市",name:"國立台灣大學醫學院附設醫院",level:.heavy,purpose:"",phone:"0223123456",address:"臺北市中正區中山南路７、８號；常德街１號",totalBeds:2270,icuBeds:230,erBeds:120),
        .init(id:"ER006",region:.north,city:"臺北市",name:"臺北醫學大學附設醫院",level:.heavy,purpose:"",phone:"0227372181",address:"臺北市信義區吳興街２５2號、250號",totalBeds:738,icuBeds:59,erBeds:27),
        .init(id:"ER007",region:.north,city:"臺北市",name:"三軍總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"",address:"臺北市內湖區成功路二段325號；臺北市中正區汀州路3段40號",totalBeds:2248,icuBeds:143,erBeds:57),
        .init(id:"ER008",region:.north,city:"臺北市",name:"康寧醫院",level:.moderate,purpose:"",phone:"26345500",address:"臺北市內湖區成功路五段４２０巷２６號",totalBeds:2248,icuBeds:143,erBeds:57),
        .init(id:"ER009",region:.north,city:"臺北市",name:"振興醫院",level:.moderate,purpose:"",phone:"0228264400",address:"臺北市北投區振興街４５號",totalBeds:5193,icuBeds:304,erBeds:89),
        .init(id:"ER010",region:.north,city:"臺北市",name:"臺北榮民總醫院",level:.heavy,purpose:"",phone:"0228712121",address:"臺北市北投區石牌路二段201號、322號",totalBeds:2799,icuBeds:304,erBeds:89),
        .init(id:"ER011",region:.north,city:"臺北市",name:"新光吳火獅紀念醫院",level:.moderate,purpose:"",phone:"0228332211",address:"臺北市士林區文昌路95號及士商路51號、51號2樓、51號3樓、51號4樓、51號5樓、51號6樓、51號7樓、53號、55號、57號、臺北市士林區基河路252號1樓",totalBeds:825,icuBeds:62,erBeds:36),
        .init(id:"ER012",region:.north,city:"臺北市",name:"中心綜合醫院",level:.moderate,purpose:"",phone:"0227510221",address:"臺北市大安區忠孝東路四段７７號",totalBeds:1853,icuBeds:96,erBeds:59),
        .init(id:"ER013",region:.north,city:"臺北市",name:"國泰綜合醫院",level:.moderate,purpose:"",phone:"0227082121",address:"臺北市大安區仁愛路四段266巷6號，280號",totalBeds:810,icuBeds:96,erBeds:59),
        .init(id:"ER014",region:.north,city:"臺北市",name:"國立臺灣大學醫學院附設醫院癌醫中心分院",level:.heavy,purpose:"",phone:"0223220322",address:"臺北市大安區基隆路 3段155巷57號",totalBeds:1853,icuBeds:96,erBeds:59),
        .init(id:"ER015",region:.north,city:"臺北市",name:"臺北市立萬芳醫院",level:.moderate,purpose:"",phone:"0229307930",address:"臺北市文山區興隆路三段111號",totalBeds:726,icuBeds:50,erBeds:34),
        .init(id:"ER016",region:.north,city:"臺北市",name:"三軍總醫院松山分院附設民眾診療服務處",level:.moderate,purpose:"",phone:"0227462151",address:"臺北市松山區健康路１３１號",totalBeds:1089,icuBeds:45,erBeds:28),
        .init(id:"ER017",region:.north,city:"臺北市",name:"博仁綜合醫院",level:.moderate,purpose:"",phone:"0225786677",address:"臺北市松山區光復北路66號、68號地下一層、68號、68號2至7樓、68號2樓之1至7樓之1、68號2樓之2至7樓之2",totalBeds:1089,icuBeds:45,erBeds:28),
        .init(id:"ER018",region:.north,city:"臺北市",name:"臺安醫院",level:.moderate,purpose:"",phone:"0227718151",address:"臺北市松山區八德路二段424,426號",totalBeds:442,icuBeds:45,erBeds:28),
        .init(id:"ER019",region:.north,city:"臺北市",name:"台北長庚紀念醫院",level:.moderate,purpose:"",phone:"0227135211",address:"臺北市松山區敦化北路199號、197號、臺北市松山區敦化北路199巷6號",totalBeds:259,icuBeds:45,erBeds:28),
        .init(id:"ER020",region:.north,city:"臺北市",name:"西園醫院",level:.moderate,purpose:"",phone:"0223329888",address:"臺北市萬華區西園路二段266、268、270、272、276號、185、187、189號",totalBeds:409,icuBeds:8,erBeds:9),
        .init(id:"ER021",region:.north,city:"新北市",name:"恩主公醫院",level:.moderate,purpose:"",phone:"0226723456",address:"新北市三峽區復興路399號、中山路198、258號",totalBeds:602,icuBeds:30,erBeds:33),
        .init(id:"ER022",region:.north,city:"新北市",name:"宏仁醫院",level:.moderate,purpose:"",phone:"29788877",address:"新北市三重區水漾路一段一五八號",totalBeds:777,icuBeds:43,erBeds:25),
        .init(id:"ER023",region:.north,city:"新北市",name:"新北市立聯合醫院",level:.moderate,purpose:"",phone:"0229829111",address:"新北市三重區新北大道1段3號、3之1號",totalBeds:777,icuBeds:43,erBeds:25),
        .init(id:"ER024",region:.north,city:"新北市",name:"衛生福利部雙和醫院",level:.moderate,purpose:"",phone:"22490088",address:"新北市中和區中正路291號醫療大樓地下2層至地上12層、中和區圓通路301號教學研究大樓及生醫科技大樓2幢",totalBeds:1434,icuBeds:85,erBeds:46),
        .init(id:"ER025",region:.north,city:"新北市",name:"新北市立土城醫院",level:.moderate,purpose:"",phone:"0222630588",address:"新北市土城區金城路二段6號",totalBeds:1115,icuBeds:58,erBeds:43),
        .init(id:"ER026",region:.north,city:"新北市",name:"台北慈濟醫院",level:.moderate,purpose:"",phone:"0266289779",address:"新北市新店區建國路277號地上1、3、4樓及289號地下1至3樓至地上1至15樓",totalBeds:1165,icuBeds:149,erBeds:70),
        .init(id:"ER027",region:.north,city:"新北市",name:"耕莘醫院",level:.moderate,purpose:"",phone:"0222193391/0222123066",address:"新北市新店區中正路362號",totalBeds:2676,icuBeds:149,erBeds:70),
        .init(id:"ER028",region:.north,city:"新北市",name:"新泰綜合醫院",level:.moderate,purpose:"",phone:"",address:"新北市新莊區新樹路176號",totalBeds:1675,icuBeds:73,erBeds:31),
        .init(id:"ER029",region:.north,city:"新北市",name:"衛生福利部臺北醫院",level:.moderate,purpose:"",phone:"022765566",address:"新北市新莊區思源路127號、長青街6號2樓、3樓",totalBeds:1675,icuBeds:73,erBeds:31),
        .init(id:"ER030",region:.north,city:"新北市",name:"亞東紀念醫院",level:.moderate,purpose:"",phone:"0289667000",address:"新北市板橋區南雅南路二段21號及高爾富路300號",totalBeds:1122,icuBeds:119,erBeds:67),
        .init(id:"ER031",region:.north,city:"新北市",name:"仁愛醫院",level:.moderate,purpose:"",phone:"0226834567",address:"新北市樹林區文化街9號(地下1、2樓及地上1樓至8樓)",totalBeds:189,icuBeds:6,erBeds:8),
        .init(id:"ER032",region:.north,city:"新北市",name:"永和耕莘醫院",level:.moderate,purpose:"",phone:"0229286060",address:"新北市永和區中興街80號地下1樓至地上6樓及國光路123號地下3樓至地上11樓",totalBeds:359,icuBeds:21,erBeds:10),
        .init(id:"ER033",region:.north,city:"新北市",name:"汐止國泰綜合醫院",level:.moderate,purpose:"",phone:"26482121",address:"新北市汐止區建成路59巷2號地下4樓至地上12樓",totalBeds:642,icuBeds:46,erBeds:31),
        .init(id:"ER034",region:.north,city:"新北市",name:"輔仁大學附設醫院",level:.heavy,purpose:"",phone:"0285128888",address:"新北市泰山區貴子路69號(地下4層、地上1至13層、15層)",totalBeds:685,icuBeds:63,erBeds:23),
        .init(id:"ER035",region:.north,city:"新北市",name:"淡水馬偕紀念醫院",level:.moderate,purpose:"",phone:"028094661",address:"新北市淡水區民生路四十五號、民權路47號B1~11樓",totalBeds:1009,icuBeds:61,erBeds:22),
        .init(id:"ER036",region:.north,city:"新北市",name:"國立臺灣大學醫學院附設醫院金山分院",level:.heavy,purpose:"",phone:"24989898",address:"新北市金山區五湖里玉爐路7號",totalBeds:86,icuBeds:0,erBeds:5),
        .init(id:"ER037",region:.north,city:"桃園市",name:"中壢長榮醫院",level:.moderate,purpose:"",phone:"034631230",address:"桃園市中壢區環中東路150號",totalBeds:983,icuBeds:37,erBeds:22),
        .init(id:"ER038",region:.north,city:"桃園市",name:"天晟醫院",level:.moderate,purpose:"",phone:"034629292",address:"桃園市中壢區延平路155號",totalBeds:320,icuBeds:37,erBeds:22),
        .init(id:"ER039",region:.north,city:"桃園市",name:"聯新國際醫院",level:.moderate,purpose:"",phone:"034941234",address:"桃園市平鎮區廣泰路七七號、桃園市平鎮區延平路二段430巷115號",totalBeds:936,icuBeds:46,erBeds:19),
        .init(id:"ER040",region:.north,city:"桃園市",name:"衛生福利部桃園醫院新屋分院",level:.moderate,purpose:"",phone:"034971989",address:"桃園市新屋區新屋里14鄰新福二路六號",totalBeds:234,icuBeds:6,erBeds:6),
        .init(id:"ER041",region:.north,city:"桃園市",name:"敏盛綜合醫院",level:.moderate,purpose:"",phone:"033179599",address:"桃園市桃園區經國路168號",totalBeds:665,icuBeds:157,erBeds:80),
        .init(id:"ER042",region:.north,city:"桃園市",name:"聖保祿醫院",level:.moderate,purpose:"",phone:"033613141",address:"桃園市桃園區建新街123號",totalBeds:427,icuBeds:157,erBeds:80),
        .init(id:"ER043",region:.north,city:"桃園市",name:"臺北榮民總醫院桃園分院",level:.heavy,purpose:"",phone:"033384889",address:"桃園市桃園區成功路3段100號",totalBeds:650,icuBeds:157,erBeds:80),
        .init(id:"ER044",region:.north,city:"桃園市",name:"衛生福利部桃園醫院",level:.moderate,purpose:"",phone:"033699721",address:"桃園市桃園區中山路1492號",totalBeds:3543,icuBeds:157,erBeds:80),
        .init(id:"ER045",region:.north,city:"桃園市",name:"天成醫院",level:.moderate,purpose:"",phone:"034782350",address:"桃園市楊梅區中山北路一段三五六號",totalBeds:265,icuBeds:25,erBeds:20),
        .init(id:"ER046",region:.north,city:"桃園市",name:"怡仁綜合醫院",level:.moderate,purpose:"",phone:"034855566",address:"桃園市楊梅區楊新北路三二一巷三０號",totalBeds:310,icuBeds:25,erBeds:20),
        .init(id:"ER047",region:.north,city:"桃園市",name:"國軍桃園總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"032623301",address:"桃園市龍潭區中興路168號",totalBeds:800,icuBeds:44,erBeds:20),
        .init(id:"ER048",region:.north,city:"桃園市",name:"林口長庚紀念醫院",level:.moderate,purpose:"",phone:"033281200",address:"桃園市龜山區公西里復興街5號、5之7號及文化一路15號",totalBeds:3715,icuBeds:305,erBeds:162),
        .init(id:"ER049",region:.north,city:"桃園市",name:"桃園長庚紀念醫院",level:.moderate,purpose:"",phone:"033196200",address:"桃園市龜山區舊路里頂湖路123號、123之1號",totalBeds:4234,icuBeds:305,erBeds:162),
        .init(id:"ER050",region:.north,city:"新竹市",name:"國立臺灣大學醫學院附設醫院新竹臺大分院新竹醫院",level:.heavy,purpose:"",phone:"035326151",address:"新竹市北區金華里經國路一段442巷25號",totalBeds:1270,icuBeds:57,erBeds:42),
        .init(id:"ER051",region:.north,city:"新竹市",name:"國軍桃園總醫院新竹分院附設民眾診療服務處",level:.moderate,purpose:"",phone:"035348181",address:"新竹市北區武陵路3號",totalBeds:1270,icuBeds:57,erBeds:42),
        .init(id:"ER052",region:.north,city:"新竹市",name:"南門綜合醫院",level:.moderate,purpose:"",phone:"035261122",address:"新竹市東區成功里林森路20號",totalBeds:1197,icuBeds:72,erBeds:91),
        .init(id:"ER053",region:.north,city:"新竹市",name:"新竹馬偕紀念醫院",level:.moderate,purpose:"",phone:"036119595",address:"新竹市東區光復里光復路二段690號",totalBeds:1197,icuBeds:72,erBeds:91),
        .init(id:"ER054",region:.north,city:"新竹市",name:"新竹國泰綜合醫院",level:.moderate,purpose:"",phone:"035278999",address:"新竹市東區福德里中華路二段六七八號及六七八號之一",totalBeds:1197,icuBeds:72,erBeds:91),
        .init(id:"ER055",region:.north,city:"新竹市",name:"新竹市立馬偕兒童醫院",level:.children,purpose:"",phone:"035719999",address:"新竹市東區建功里建功二路28號",totalBeds:1197,icuBeds:72,erBeds:91),
        .init(id:"ER056",region:.north,city:"新竹縣",name:"仁慈醫院",level:.moderate,purpose:"",phone:"035993500",address:"新竹縣湖口鄉忠孝路２９號",totalBeds:339,icuBeds:11,erBeds:9),
        .init(id:"ER057",region:.north,city:"新竹縣",name:"中國醫藥大學新竹附設醫院",level:.moderate,purpose:"",phone:"035580558",address:"新竹縣竹北市興隆路一段199號",totalBeds:2022,icuBeds:103,erBeds:65),
        .init(id:"ER058",region:.north,city:"新竹縣",name:"國立臺灣大學醫學院附設醫院新竹臺大分院生醫醫院",level:.heavy,purpose:"",phone:"036677600",address:"新竹縣竹北市生醫路一段2號",totalBeds:2022,icuBeds:103,erBeds:65),
        .init(id:"ER059",region:.north,city:"新竹縣",name:"東元綜合醫院",level:.moderate,purpose:"",phone:"035527000",address:"新竹縣竹北市縣政二路69號(竹北市光明九路9-1號牙科.精神科門診部)",totalBeds:2022,icuBeds:103,erBeds:65),
        .init(id:"ER060",region:.north,city:"新竹縣",name:"臺北榮民總醫院新竹分院",level:.heavy,purpose:"",phone:"035962134",address:"新竹縣竹東鎮中豐路一段81號",totalBeds:517,icuBeds:10,erBeds:12),
        .init(id:"ER061",region:.north,city:"苗栗縣",name:"大順醫院",level:.moderate,purpose:"",phone:"037997666",address:"苗栗縣大湖鄉明湖村13鄰中山路71號",totalBeds:20,icuBeds:0,erBeds:2),
        .init(id:"ER062",region:.north,city:"苗栗縣",name:"苑裡李綜合醫院",level:.moderate,purpose:"",phone:"862387",address:"苗栗縣苑裡鎮和平路168號、苗栗縣苑裡鎮中華路137號",totalBeds:236,icuBeds:15,erBeds:6),
        .init(id:"ER063",region:.north,city:"苗栗縣",name:"大千綜合醫院",level:.moderate,purpose:"",phone:"037357125",address:"苗栗縣苗栗市大同路133號1至6樓(81栗建管苗字第405號)、大同路133號1至4樓(77栗建管苗字第00414號)信義路23號地下層（一）及1至7樓(85栗建管苗字第287號)恭敬路36號地下第3層及1至9樓 (97栗商建苗使字第00112號)、信義街36號1至8樓（101）栗商建苗使字第00127號",totalBeds:515,icuBeds:73,erBeds:40),
        .init(id:"ER064",region:.north,city:"苗栗縣",name:"衛生福利部苗栗醫院",level:.moderate,purpose:"",phone:"037261920",address:"苗栗縣苗栗市為公路747號",totalBeds:1351,icuBeds:73,erBeds:40),
        .init(id:"ER065",region:.north,city:"苗栗縣",name:"為恭紀念醫院",level:.moderate,purpose:"",phone:"037676811",address:"苗栗縣頭份市信義路128號(信義院區: 信義路128號及仁愛路125號5樓、仁愛院區:仁愛路116號、東興院區:水源路417巷11號及13號)",totalBeds:1032,icuBeds:37,erBeds:25),
        .init(id:"ER066",region:.central,city:"臺中市",name:"澄清綜合醫院",level:.moderate,purpose:"",phone:"0424632000",address:"臺中市中區平等街139號",totalBeds:502,icuBeds:31,erBeds:10),
        .init(id:"ER067",region:.central,city:"臺中市",name:"中國醫藥大學兒童醫院",level:.children,purpose:"",phone:"0422052121",address:"臺中市北區學士路95號(1樓至7樓)、學士路2號(1樓部分空間)、育德路1號(8樓部分空間)",totalBeds:2640,icuBeds:195,erBeds:64),
        .init(id:"ER068",region:.central,city:"臺中市",name:"中國醫藥大學附設醫院",level:.heavy,purpose:"",phone:"0422052121",address:"臺中市北區育德路二號",totalBeds:2054,icuBeds:195,erBeds:64),
        .init(id:"ER069",region:.central,city:"臺中市",name:"國軍臺中總醫院中清分院附設民眾診療服務處",level:.moderate,purpose:"",phone:"0422037320",address:"臺中市北區忠明路500號",totalBeds:2640,icuBeds:195,erBeds:64),
        .init(id:"ER070",region:.central,city:"臺中市",name:"中山醫學大學附設醫院",level:.heavy,purpose:"",phone:"0424739595",address:"臺中市南區建國北路一段一一○號",totalBeds:1305,icuBeds:113,erBeds:36),
        .init(id:"ER071",region:.central,city:"臺中市",name:"林新醫院",level:.moderate,purpose:"",phone:"0422586688",address:"臺中市南屯區惠中路3段36號",totalBeds:805,icuBeds:35,erBeds:18),
        .init(id:"ER072",region:.central,city:"臺中市",name:"大甲李綜合醫院",level:.moderate,purpose:"",phone:"0426862288",address:"臺中市大甲區八德街2號",totalBeds:383,icuBeds:21,erBeds:6),
        .init(id:"ER073",region:.central,city:"臺中市",name:"大里仁愛醫院",level:.moderate,purpose:"",phone:"0424819900",address:"臺中市大里區東榮路４８３號",totalBeds:839,icuBeds:40,erBeds:25),
        .init(id:"ER074",region:.central,city:"臺中市",name:"霧峰澄清醫院",level:.moderate,purpose:"",phone:"0424922000",address:"臺中市大里區成功路55號",totalBeds:839,icuBeds:40,erBeds:25),
        .init(id:"ER075",region:.central,city:"臺中市",name:"清泉醫院",level:.moderate,purpose:"",phone:"0425605600",address:"臺中市大雅區三和里雅潭路四段80號",totalBeds:229,icuBeds:10,erBeds:5),
        .init(id:"ER076",region:.central,city:"臺中市",name:"國軍臺中總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"0423934191",address:"臺中市太平區中山路二段３４８號",totalBeds:1138,icuBeds:65,erBeds:35),
        .init(id:"ER077",region:.central,city:"臺中市",name:"賢德醫院",level:.moderate,purpose:"",phone:"0422732551",address:"臺中市太平區宜昌路420號",totalBeds:1138,icuBeds:65,erBeds:35),
        .init(id:"ER078",region:.central,city:"臺中市",name:"長安醫院",level:.moderate,purpose:"",phone:"",address:"臺中市太平區永平路1段9號",totalBeds:1138,icuBeds:65,erBeds:35),
        .init(id:"ER079",region:.central,city:"臺中市",name:"東勢區農會附設農民醫院",level:.moderate,purpose:"",phone:"0425771919",address:"臺中市東勢區豐勢路２９７號",totalBeds:93,icuBeds:6,erBeds:2),
        .init(id:"ER080",region:.central,city:"臺中市",name:"童綜合醫院",level:.moderate,purpose:"",phone:"0426581919",address:"臺中市梧棲區臺灣大道八段699號",totalBeds:1498,icuBeds:90,erBeds:30),
        .init(id:"ER081",region:.central,city:"臺中市",name:"光田綜合醫院",level:.moderate,purpose:"",phone:"0426625111",address:"臺中市沙鹿區沙田路117號（含大同街5-2號）",totalBeds:1194,icuBeds:83,erBeds:21),
        .init(id:"ER082",region:.central,city:"臺中市",name:"台中慈濟醫院",level:.moderate,purpose:"",phone:"0436060666",address:"臺中市潭子區豐興路一段66、88號",totalBeds:898,icuBeds:55,erBeds:22),
        .init(id:"ER083",region:.central,city:"臺中市",name:"烏日林新醫院",level:.moderate,purpose:"",phone:"0423388766",address:"臺中市烏日區榮和路168號",totalBeds:513,icuBeds:20,erBeds:12),
        .init(id:"ER084",region:.central,city:"臺中市",name:"衛生福利部臺中醫院",level:.moderate,purpose:"",phone:"0422294411",address:"臺中市西區廣民里三民路1段199號",totalBeds:1035,icuBeds:30,erBeds:6),
        .init(id:"ER085",region:.central,city:"臺中市",name:"澄清綜合醫院中港分院",level:.moderate,purpose:"",phone:"0424632000",address:"臺中市西屯區臺灣大道4段966號",totalBeds:2417,icuBeds:187,erBeds:100),
        .init(id:"ER086",region:.central,city:"臺中市",name:"臺中榮民總醫院",level:.heavy,purpose:"",phone:"0423592525",address:"臺中市西屯區臺灣大道4段1650號",totalBeds:1464,icuBeds:187,erBeds:100),
        .init(id:"ER087",region:.central,city:"臺中市",name:"衛生福利部豐原醫院",level:.moderate,purpose:"",phone:"0425271180",address:"臺中市豐原區安康路１００號",totalBeds:1107,icuBeds:53,erBeds:20),
        .init(id:"ER088",region:.central,city:"臺中市",name:"亞洲大學附屬醫院",level:.heavy,purpose:"",phone:"0437061668",address:"臺中市霧峰區福新路222號",totalBeds:545,icuBeds:40,erBeds:10),
        .init(id:"ER089",region:.central,city:"彰化縣",name:"二林基督教醫院",level:.moderate,purpose:"",phone:"048960128",address:"彰化縣二林鎮南光里大成路一段558號、安和街40巷28號2樓",totalBeds:279,icuBeds:18,erBeds:13),
        .init(id:"ER090",region:.central,city:"彰化縣",name:"員榮醫院",level:.moderate,purpose:"",phone:"048326161",address:"彰化縣員林市中正路201號",totalBeds:200,icuBeds:66,erBeds:63),
        .init(id:"ER091",region:.central,city:"彰化縣",name:"員林基督教醫院",level:.moderate,purpose:"",phone:"048381456",address:"彰化縣員林市南平里莒光路456號",totalBeds:150,icuBeds:66,erBeds:63),
        .init(id:"ER092",region:.central,city:"彰化縣",name:"衛生福利部彰化醫院",level:.moderate,purpose:"",phone:"048298686",address:"彰化縣埔心鄉中正路二段80號",totalBeds:500,icuBeds:16,erBeds:5),
        .init(id:"ER093",region:.central,city:"彰化縣",name:"彰化基督教醫院",level:.moderate,purpose:"",phone:"047238595",address:"彰化縣彰化市南校街135號、中華路176號、旭光路235、旭光路320號(地下2樓至地下5樓、地上12樓至地上14樓)",totalBeds:2862,icuBeds:265,erBeds:110),
        .init(id:"ER094",region:.central,city:"彰化縣",name:"漢銘基督教醫院",level:.moderate,purpose:"",phone:"047113456",address:"彰化縣彰化市南興里中山路一段３６６號",totalBeds:168,icuBeds:265,erBeds:110),
        .init(id:"ER095",region:.central,city:"彰化縣",name:"秀傳紀念醫院",level:.moderate,purpose:"",phone:"047256166",address:"彰化縣彰化市南瑤里中山路1段536、542號(醫療大樓)、彰化縣彰化市南瑤里南平街61巷6號(健檢中心)、彰化縣彰化市南瑤里中山路1段530巷123號(醫研大樓)",totalBeds:2862,icuBeds:265,erBeds:110),
        .init(id:"ER096",region:.central,city:"彰化縣",name:"鹿港基督教醫院",level:.moderate,purpose:"",phone:"047779595",address:"彰化縣鹿港鎮中正路480號",totalBeds:1562,icuBeds:56,erBeds:18),
        .init(id:"ER097",region:.central,city:"彰化縣",name:"彰濱秀傳紀念醫院",level:.moderate,purpose:"",phone:"047813888",address:"彰化縣鹿港鎮鹿工路6號、6-2號",totalBeds:1020,icuBeds:56,erBeds:18),
        .init(id:"ER098",region:.central,city:"南投縣",name:"南投基督教醫院",level:.moderate,purpose:"",phone:"0492225535",address:"南投縣南投市中興路870號",totalBeds:123,icuBeds:47,erBeds:12),
        .init(id:"ER099",region:.central,city:"南投縣",name:"衛生福利部南投醫院",level:.moderate,purpose:"",phone:"049231150",address:"南投縣南投市復興路478號",totalBeds:415,icuBeds:47,erBeds:12),
        .init(id:"ER100",region:.central,city:"南投縣",name:"埔里基督教醫院",level:.moderate,purpose:"",phone:"0492912151",address:"南投縣埔里鎮鐵山路一號",totalBeds:309,icuBeds:26,erBeds:20),
        .init(id:"ER101",region:.central,city:"南投縣",name:"臺中榮民總醫院埔里分院",level:.heavy,purpose:"",phone:"0492998911",address:"南投縣埔里鎮蜈蚣里榮光路1號",totalBeds:340,icuBeds:26,erBeds:20),
        .init(id:"ER102",region:.central,city:"南投縣",name:"東華醫院",level:.moderate,purpose:"",phone:"0492658949",address:"南投縣竹山鎮集山路三段272巷16號",totalBeds:420,icuBeds:33,erBeds:20),
        .init(id:"ER103",region:.central,city:"南投縣",name:"竹山秀傳醫院",level:.moderate,purpose:"",phone:"0492624266",address:"南投縣竹山鎮集山路2段75號",totalBeds:290,icuBeds:33,erBeds:20),
        .init(id:"ER104",region:.central,city:"南投縣",name:"佑民醫院",level:.moderate,purpose:"",phone:"0492358151",address:"南投縣草屯鎮太平路一段200號",totalBeds:1405,icuBeds:23,erBeds:16),
        .init(id:"ER105",region:.central,city:"南投縣",name:"曾漢棋綜合醫院",level:.moderate,purpose:"",phone:"0492314149",address:"南投縣草屯鎮虎山路９１５號",totalBeds:1405,icuBeds:23,erBeds:16),
        .init(id:"ER106",region:.yunjianan,city:"雲林縣",name:"中國醫藥大學北港附設醫院",level:.moderate,purpose:"",phone:"057837901",address:"雲林縣北港鎮新德路１２３號",totalBeds:658,icuBeds:40,erBeds:11),
        .init(id:"ER107",region:.yunjianan,city:"雲林縣",name:"國立成功大學醫學院附設醫院斗六分院",level:.heavy,purpose:"",phone:"055322017",address:"雲林縣斗六市莊敬路345號",totalBeds:1669,icuBeds:74,erBeds:51),
        .init(id:"ER108",region:.yunjianan,city:"雲林縣",name:"國立臺灣大學醫學院附設醫院雲林分院",level:.heavy,purpose:"",phone:"055323911",address:"雲林縣斗六市雲林路二段579號",totalBeds:1669,icuBeds:74,erBeds:51),
        .init(id:"ER109",region:.yunjianan,city:"雲林縣",name:"若瑟醫院",level:.moderate,purpose:"",phone:"056337333",address:"雲林縣虎尾鎮新生路74號(民權路2號)",totalBeds:381,icuBeds:20,erBeds:10),
        .init(id:"ER110",region:.yunjianan,city:"雲林縣",name:"雲林基督教醫院",level:.moderate,purpose:"",phone:"055871111",address:"雲林縣西螺鎮新豐里市場南路371、375號",totalBeds:332,icuBeds:24,erBeds:12),
        .init(id:"ER111",region:.yunjianan,city:"雲林縣",name:"雲林長庚紀念醫院",level:.moderate,purpose:"",phone:"056915151",address:"雲林縣麥寮鄉中興村工業路1500號",totalBeds:166,icuBeds:6,erBeds:9),
        .init(id:"ER112",region:.yunjianan,city:"嘉義市",name:"天主教聖馬爾定醫院",level:.moderate,purpose:"",phone:"052756000",address:"嘉義市東區短竹里大雅路二段565號",totalBeds:1949,icuBeds:139,erBeds:63),
        .init(id:"ER113",region:.yunjianan,city:"嘉義市",name:"嘉義基督教醫院",level:.moderate,purpose:"",phone:"052765041",address:"嘉義市東區中庄里忠孝路539號；東區後湖里保建街100號；東區頂庄里忠孝路642號；中庄里忠孝路539-3號；中庄里忠孝路539-1號3~7樓",totalBeds:1949,icuBeds:139,erBeds:63),
        .init(id:"ER114",region:.yunjianan,city:"嘉義市",name:"陽明醫院",level:.moderate,purpose:"",phone:"052284567",address:"嘉義市東區吳鳳北路252號",totalBeds:345,icuBeds:139,erBeds:63),
        .init(id:"ER115",region:.yunjianan,city:"嘉義市",name:"臺中榮民總醫院嘉義分院",level:.heavy,purpose:"",phone:"052359630",address:"嘉義市西區劉厝里世賢路二段６００號",totalBeds:1538,icuBeds:63,erBeds:14),
        .init(id:"ER116",region:.yunjianan,city:"嘉義市",name:"衛生福利部嘉義醫院",level:.moderate,purpose:"",phone:"052319090",address:"嘉義市西區北港路312號",totalBeds:1538,icuBeds:63,erBeds:14),
        .init(id:"ER117",region:.yunjianan,city:"嘉義縣",name:"大林慈濟醫院",level:.moderate,purpose:"",phone:"052648000",address:"嘉義縣大林鎮平林里民生路2號",totalBeds:926,icuBeds:59,erBeds:15),
        .init(id:"ER118",region:.yunjianan,city:"嘉義縣",name:"衛生福利部朴子醫院",level:.moderate,purpose:"",phone:"053790600",address:"嘉義縣朴子市永和里5鄰應菜埔４２－５０號",totalBeds:1526,icuBeds:106,erBeds:34),
        .init(id:"ER119",region:.yunjianan,city:"嘉義縣",name:"嘉義長庚紀念醫院",level:.moderate,purpose:"",phone:"053621000",address:"嘉義縣朴子市仁和里長庚一路六號、嘉朴路西段八號",totalBeds:1526,icuBeds:106,erBeds:34),
        .init(id:"ER120",region:.yunjianan,city:"臺南市",name:"衛生福利部臺南醫院",level:.moderate,purpose:"",phone:"062200055",address:"臺南市中西區中山路125號",totalBeds:1322,icuBeds:56,erBeds:18),
        .init(id:"ER121",region:.yunjianan,city:"臺南市",name:"郭綜合醫院",level:.moderate,purpose:"",phone:"062221111",address:"臺南市中西區民生路2段6.8.10.12.14.18.20.22.23.24.25.27.44號及40、42號1、2樓",totalBeds:1322,icuBeds:56,erBeds:18),
        .init(id:"ER122",region:.yunjianan,city:"臺南市",name:"佳里奇美醫院",level:.moderate,purpose:"",phone:"067263333",address:"臺南市佳里區佳興里佳里興606號",totalBeds:260,icuBeds:21,erBeds:20),
        .init(id:"ER123",region:.yunjianan,city:"臺南市",name:"國立成功大學醫學院附設醫院",level:.heavy,purpose:"",phone:"062353535",address:"臺南市北區勝利路１３８號",totalBeds:1465,icuBeds:126,erBeds:75),
        .init(id:"ER124",region:.yunjianan,city:"臺南市",name:"臺南市立安南醫院",level:.moderate,purpose:"",phone:"063553111",address:"臺南市安南區長和路二段66號",totalBeds:1007,icuBeds:62,erBeds:21),
        .init(id:"ER125",region:.yunjianan,city:"臺南市",name:"衛生福利部臺南醫院新化分院",level:.moderate,purpose:"",phone:"065911929",address:"臺南市新化區那拔里牧場72號",totalBeds:284,icuBeds:6,erBeds:6),
        .init(id:"ER126",region:.yunjianan,city:"臺南市",name:"衛生福利部新營醫院",level:.moderate,purpose:"",phone:"066351131",address:"臺南市新營區信義街73號",totalBeds:435,icuBeds:14,erBeds:11),
        .init(id:"ER127",region:.yunjianan,city:"臺南市",name:"台南市立醫院",level:.moderate,purpose:"",phone:"062609926",address:"臺南市東區崇德路670號",totalBeds:1008,icuBeds:72,erBeds:35),
        .init(id:"ER128",region:.yunjianan,city:"臺南市",name:"台南新樓醫院",level:.moderate,purpose:"",phone:"062748316",address:"臺南市東區東門路1段57號",totalBeds:1008,icuBeds:72,erBeds:35),
        .init(id:"ER129",region:.yunjianan,city:"臺南市",name:"柳營奇美醫院",level:.moderate,purpose:"",phone:"066226999",address:"臺南市柳營區太康里201號",totalBeds:876,icuBeds:67,erBeds:24),
        .init(id:"ER130",region:.yunjianan,city:"臺南市",name:"奇美醫院",level:.moderate,purpose:"",phone:"062812811",address:"臺南市永康區中華路901號",totalBeds:2076,icuBeds:129,erBeds:84),
        .init(id:"ER131",region:.yunjianan,city:"臺南市",name:"高雄榮民總醫院臺南分院",level:.heavy,purpose:"",phone:"063125101",address:"臺南市永康區復興路427號",totalBeds:2076,icuBeds:129,erBeds:84),
        .init(id:"ER132",region:.yunjianan,city:"臺南市",name:"麻豆新樓醫院",level:.moderate,purpose:"",phone:"065702228",address:"臺南市麻豆區麻佳路一段207號",totalBeds:383,icuBeds:22,erBeds:10),
        .init(id:"ER133",region:.gaopingpeng,city:"高雄市",name:"義大大昌醫院",level:.moderate,purpose:"",phone:"5599123",address:"高雄市三民區大昌一路305號地下3樓至地上10樓、307號地上1樓、309號地下1樓至地上3樓、309號地上6樓至地上10樓及311號地下1樓至地上1樓",totalBeds:2528,icuBeds:151,erBeds:80),
        .init(id:"ER134",region:.gaopingpeng,city:"高雄市",name:"高雄醫學大學附設中和紀念醫院",level:.heavy,purpose:"",phone:"073121101",address:"高雄市三民區十全一路100號及新興區中山一路36號",totalBeds:1690,icuBeds:151,erBeds:80),
        .init(id:"ER135",region:.gaopingpeng,city:"高雄市",name:"高雄市立大同醫院",level:.moderate,purpose:"",phone:"",address:"高雄市前金區中華三路68號",totalBeds:801,icuBeds:45,erBeds:40),
        .init(id:"ER136",region:.gaopingpeng,city:"高雄市",name:"高雄市立小港醫院",level:.moderate,purpose:"",phone:"078036783",address:"高雄市小港區山明里山明路482號B1-10樓、宏光街289號B3-10樓",totalBeds:750,icuBeds:30,erBeds:40),
        .init(id:"ER137",region:.gaopingpeng,city:"高雄市",name:"高雄醫學大學附設高醫岡山醫院",level:.heavy,purpose:"",phone:"076261000",address:"高雄市岡山區捷安路8號地下3樓至2樓、6樓及10樓",totalBeds:692,icuBeds:34,erBeds:39),
        .init(id:"ER138",region:.gaopingpeng,city:"高雄市",name:"高雄市立岡山醫院",level:.moderate,purpose:"",phone:"076222131",address:"高雄市岡山區壽天路12號",totalBeds:692,icuBeds:34,erBeds:39),
        .init(id:"ER139",region:.gaopingpeng,city:"高雄市",name:"國軍左營總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"075811648",address:"高雄市左營區軍校路５５３號",totalBeds:2431,icuBeds:134,erBeds:70),
        .init(id:"ER140",region:.gaopingpeng,city:"高雄市",name:"高雄榮民總醫院",level:.heavy,purpose:"",phone:"073422121",address:"高雄市左營區大中一路３８６號",totalBeds:1408,icuBeds:134,erBeds:70),
        .init(id:"ER141",region:.gaopingpeng,city:"高雄市",name:"衛生福利部旗山醫院",level:.moderate,purpose:"",phone:"076613811",address:"高雄市旗山區中學路６０號、東新街25巷8號1-2樓",totalBeds:543,icuBeds:23,erBeds:10),
        .init(id:"ER142",region:.gaopingpeng,city:"高雄市",name:"健仁醫院",level:.moderate,purpose:"",phone:"073517166",address:"高雄市楠梓區楠陽路１３６號朝明路１３０巷７弄１號１-５樓",totalBeds:479,icuBeds:13,erBeds:4),
        .init(id:"ER143",region:.gaopingpeng,city:"高雄市",name:"義大癌治療醫院",level:.moderate,purpose:"",phone:"076150022",address:"高雄市燕巢區角宿里義大路21號B2-10F",totalBeds:1916,icuBeds:105,erBeds:71),
        .init(id:"ER144",region:.gaopingpeng,city:"高雄市",name:"義大醫院",level:.moderate,purpose:"",phone:"076150011",address:"高雄市燕巢區角宿里義大路1號",totalBeds:1916,icuBeds:105,erBeds:71),
        .init(id:"ER145",region:.gaopingpeng,city:"高雄市",name:"國軍高雄總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"077496751",address:"高雄市苓雅區建軍路５號",totalBeds:2808,icuBeds:136,erBeds:68),
        .init(id:"ER146",region:.gaopingpeng,city:"高雄市",name:"聖功醫院",level:.moderate,purpose:"",phone:"072238153",address:"高雄市苓雅區建國一路352號",totalBeds:2808,icuBeds:136,erBeds:68),
        .init(id:"ER147",region:.gaopingpeng,city:"高雄市",name:"阮綜合醫院",level:.moderate,purpose:"",phone:"073351121",address:"高雄市苓雅區成功一路156號1-3樓及162號B1-10樓.四維四路136號B4-12樓.166號B2-13樓.永昌街49號1-6樓",totalBeds:2808,icuBeds:136,erBeds:68),
        .init(id:"ER148",region:.gaopingpeng,city:"高雄市",name:"高雄市立民生醫院",level:.moderate,purpose:"",phone:"077511131",address:"高雄市苓雅區凱旋二路134號",totalBeds:2808,icuBeds:136,erBeds:68),
        .init(id:"ER149",region:.gaopingpeng,city:"高雄市",name:"高雄長庚紀念醫院",level:.moderate,purpose:"",phone:"077317123",address:"高雄市鳥松區大埤路１２３號",totalBeds:2751,icuBeds:207,erBeds:100),
        .init(id:"ER150",region:.gaopingpeng,city:"高雄市",name:"高雄市立鳳山醫院",level:.moderate,purpose:"",phone:"077418151",address:"高雄市鳳山區經武路42號、42-1號",totalBeds:476,icuBeds:20,erBeds:13),
        .init(id:"ER151",region:.gaopingpeng,city:"高雄市",name:"高雄市立聯合醫院",level:.moderate,purpose:"",phone:"075552565",address:"高雄市鼓山區中華一路976號",totalBeds:503,icuBeds:29,erBeds:20),
        .init(id:"ER152",region:.gaopingpeng,city:"屏東縣",name:"屏東榮民總醫院龍泉分院",level:.heavy,purpose:"",phone:"087702212",address:"屏東縣內埔鄉龍潭村昭勝路安平一巷一號",totalBeds:528,icuBeds:10,erBeds:8),
        .init(id:"ER153",region:.gaopingpeng,city:"屏東縣",name:"國仁醫院",level:.moderate,purpose:"",phone:"087223000",address:"屏東縣屏東市民生東路12-2號",totalBeds:2626,icuBeds:161,erBeds:81),
        .init(id:"ER154",region:.gaopingpeng,city:"屏東縣",name:"寶建醫院",level:.moderate,purpose:"",phone:"087665995",address:"屏東縣屏東市中山路119、123號",totalBeds:2626,icuBeds:161,erBeds:81),
        .init(id:"ER155",region:.gaopingpeng,city:"屏東縣",name:"屏東基督教醫院",level:.moderate,purpose:"",phone:"087363026",address:"屏東縣屏東市大連路６０號",totalBeds:2626,icuBeds:161,erBeds:81),
        .init(id:"ER156",region:.gaopingpeng,city:"屏東縣",name:"屏東榮民總醫院",level:.heavy,purpose:"",phone:"087557885",address:"屏東縣屏東市崇武里榮總東路1號",totalBeds:2626,icuBeds:161,erBeds:81),
        .init(id:"ER157",region:.gaopingpeng,city:"屏東縣",name:"衛生福利部屏東醫院",level:.moderate,purpose:"",phone:"087363011",address:"屏東縣屏東市自由路２７０號",totalBeds:2626,icuBeds:161,erBeds:81),
        .init(id:"ER158",region:.gaopingpeng,city:"屏東縣",name:"南門醫院",level:.moderate,purpose:"",phone:"08.8894568",address:"屏東縣恆春鎮南門路10號",totalBeds:200,icuBeds:14,erBeds:12),
        .init(id:"ER159",region:.gaopingpeng,city:"屏東縣",name:"恆春基督教醫院",level:.moderate,purpose:"",phone:"088892293",address:"屏東縣恆春鎮山腳里恆西路21及21-1號",totalBeds:200,icuBeds:14,erBeds:12),
        .init(id:"ER160",region:.gaopingpeng,city:"屏東縣",name:"衛生福利部恆春旅遊醫院",level:.moderate,purpose:"",phone:"088892705",address:"屏東縣恆春鎮山腳里恆南路１８８、１８８－１號",totalBeds:200,icuBeds:14,erBeds:12),
        .init(id:"ER161",region:.gaopingpeng,city:"屏東縣",name:"安泰醫院",level:.moderate,purpose:"",phone:"088329966",address:"屏東縣東港鎮中正路一段210號",totalBeds:1091,icuBeds:70,erBeds:23),
        .init(id:"ER162",region:.gaopingpeng,city:"屏東縣",name:"輔英科技大學附設醫院",level:.heavy,purpose:"",phone:"088323146",address:"屏東縣東港鎮中山路５號",totalBeds:1091,icuBeds:70,erBeds:23),
        .init(id:"ER163",region:.gaopingpeng,city:"屏東縣",name:"枋寮醫院",level:.moderate,purpose:"",phone:"08.8789991",address:"屏東縣枋寮鄉安樂村中山路139號(代表號)及枋寮鄉安樂村隆山路59號",totalBeds:208,icuBeds:12,erBeds:11),
        .init(id:"ER164",region:.gaopingpeng,city:"屏東縣",name:"潮州安泰醫院",level:.moderate,purpose:"",phone:"08.7800888",address:"屏東縣潮州鎮三星里四維路162及193號",totalBeds:159,icuBeds:8,erBeds:5),
        .init(id:"ER165",region:.gaopingpeng,city:"屏東縣",name:"大新醫院",level:.moderate,purpose:"",phone:"087962033",address:"屏東縣高樹鄉長榮村興中路208號1樓至3樓與興中路210號1樓",totalBeds:22,icuBeds:0,erBeds:1),
        .init(id:"ER166",region:.north,city:"宜蘭縣",name:"國立陽明交通大學附設醫院",level:.heavy,purpose:"",phone:"039325192",address:"宜蘭縣宜蘭市校舍路169號",totalBeds:522,icuBeds:41,erBeds:24),
        .init(id:"ER167",region:.north,city:"宜蘭縣",name:"宜蘭仁愛醫院",level:.moderate,purpose:"",phone:"039355366",address:"宜蘭縣宜蘭市中山路二段260號",totalBeds:666,icuBeds:41,erBeds:24),
        .init(id:"ER168",region:.north,city:"宜蘭縣",name:"羅東聖母醫院",level:.moderate,purpose:"",phone:"039544106",address:"宜蘭縣羅東鎮中正南路160號",totalBeds:1386,icuBeds:91,erBeds:43),
        .init(id:"ER169",region:.north,city:"宜蘭縣",name:"羅東博愛醫院",level:.moderate,purpose:"",phone:"039543131",address:"宜蘭縣羅東鎮南昌街81、83號站前南路61、63號",totalBeds:1386,icuBeds:91,erBeds:43),
        .init(id:"ER170",region:.north,city:"宜蘭縣",name:"臺北榮民總醫院蘇澳分院",level:.heavy,purpose:"",phone:"039905106",address:"宜蘭縣蘇澳鎮蘇濱路一段301號",totalBeds:280,icuBeds:9,erBeds:5),
        .init(id:"ER171",region:.east,city:"花蓮縣",name:"國軍花蓮總醫院附設民眾診療服務處",level:.moderate,purpose:"",phone:"038263151",address:"花蓮縣新城鄉嘉里路163號",totalBeds:367,icuBeds:10,erBeds:8),
        .init(id:"ER172",region:.east,city:"花蓮縣",name:"臺北榮民總醫院玉里分院",level:.heavy,purpose:"",phone:"038883141",address:"花蓮縣玉里鎮新興街９１號",totalBeds:1620,icuBeds:11,erBeds:12),
        .init(id:"ER173",region:.east,city:"花蓮縣",name:"花蓮慈濟醫院",level:.moderate,purpose:"",phone:"038561825",address:"花蓮縣花蓮市中央路三段７０７號",totalBeds:1110,icuBeds:122,erBeds:50),
        .init(id:"ER174",region:.east,city:"花蓮縣",name:"門諾醫院",level:.moderate,purpose:"",phone:"038241234",address:"花蓮縣花蓮市民權路４４號",totalBeds:1783,icuBeds:122,erBeds:50),
        .init(id:"ER175",region:.east,city:"花蓮縣",name:"衛生福利部花蓮醫院",level:.moderate,purpose:"",phone:"038358141",address:"花蓮縣花蓮市中正路600號",totalBeds:1783,icuBeds:122,erBeds:50),
        .init(id:"ER176",region:.east,city:"花蓮縣",name:"衛生福利部花蓮醫院豐濱原住民分院",level:.moderate,purpose:"",phone:"038791385",address:"花蓮縣豐濱鄉光豐路４１號",totalBeds:23,icuBeds:0,erBeds:3),
        .init(id:"ER177",region:.east,city:"花蓮縣",name:"臺北榮民總醫院鳳林分院",level:.heavy,purpose:"",phone:"038763331",address:"花蓮縣鳳林鎮中正路一段2號",totalBeds:162,icuBeds:4,erBeds:4),
        .init(id:"ER178",region:.east,city:"臺東縣",name:"台東馬偕紀念醫院",level:.moderate,purpose:"",phone:"089310150",address:"臺東縣臺東市長沙街３０３巷１號",totalBeds:1197,icuBeds:63,erBeds:21),
        .init(id:"ER179",region:.east,city:"臺東縣",name:"台東基督教醫院",level:.moderate,purpose:"",phone:"089323362",address:"臺東縣臺東市開封街３５０號",totalBeds:1197,icuBeds:63,erBeds:21),
        .init(id:"ER180",region:.east,city:"臺東縣",name:"衛生福利部臺東醫院",level:.moderate,purpose:"",phone:"089324112",address:"臺東縣臺東市五權街１號",totalBeds:1197,icuBeds:63,erBeds:21),
        .init(id:"ER181",region:.east,city:"臺東縣",name:"關山慈濟醫院",level:.moderate,purpose:"",phone:"089814880",address:"臺東縣關山鎮和平路１２５之５號",totalBeds:64,icuBeds:0,erBeds:4),
        .init(id:"ER182",region:.gaopingpeng,city:"澎湖縣",name:"三軍總醫院澎湖分院附設民眾診療服務處",level:.moderate,purpose:"",phone:"069211116",address:"澎湖縣馬公市前寮里90號1-5樓",totalBeds:483,icuBeds:23,erBeds:23),
        .init(id:"ER183",region:.gaopingpeng,city:"澎湖縣",name:"衛生福利部澎湖醫院",level:.moderate,purpose:"",phone:"069261151",address:"澎湖縣馬公市中正路10號",totalBeds:483,icuBeds:23,erBeds:23),
        .init(id:"ER184",region:.offshore,city:"金門縣",name:"衛生福利部金門醫院",level:.moderate,purpose:"",phone:"0823325461201",address:"金門縣金湖鎮復興路2號",totalBeds:304,icuBeds:10,erBeds:14),
        .init(id:"ER185",region:.offshore,city:"連江縣",name:"連江縣立醫院",level:.moderate,purpose:"",phone:"083625114",address:"連江縣南竿鄉復興村217號",totalBeds:43,icuBeds:1,erBeds:6),
    ]

    static func grouped() -> [(region: FieldHospital.Region, items: [FieldHospital])] {
        FieldHospital.Region.allCases.compactMap { r in
            let items = all.filter { $0.region == r }
            return items.isEmpty ? nil : (r, items)
        }
    }
}
