import Foundation

// Test Xiaohongshu list detection
let xiaohongshuText = """
台北必吃美食清單🧾 探店合集

1. 阿夢咖啡廳 📍中正紀念堂
   煙花女麵 $350，份量超大
   營業時間：11:00-21:30

2. Standard Bread 信義區
   杜拜巧克力吐司 $399
   韓國超紅麵包店

③ 清水茶香 大安區
   黑糖剉冰必點
   人均$150

#台北美食 #探店 #打卡
"""

let xiaohongshuURL = "https://www.xiaohongshu.com/explore/abc123"

// Test Dianping list detection  
let dianpingText = """
上海美食推薦｜大眾點評高分店鋪

1. 蟹尊苑 4.8分 ￥200/人
   地址：上海市黄浦区广东路59号
   招牌大閘蟹超級好吃

2. 老上海弄堂菜 4.5分 ￥150/人
   地址：上海市靜安區南京西路100號
   本幫菜正宗

③ 外灘景觀餐廳 4.7分 ￥500/人
   地址：上海市黄浦區中山東一路
   夜景超美
"""

let dianpingURL = "https://www.dianping.com/shop/abc123"

print("Testing Xiaohongshu text:")
print(xiaohongshuText)
print("\n---\n")
print("Testing Dianping text:")
print(dianpingText)
print("\nTest data ready for validation")
