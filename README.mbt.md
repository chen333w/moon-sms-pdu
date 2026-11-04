# moon-sms-pdu

SMS PDU 编解码，纯 MoonBit 实现，不依赖 FFI，没有 C 代码。

发短信这件事看起来简单，落到协议层就全是细节：GSM 7-bit 的 septet 要按位错位打包，
一条长短信要切成带 UDH 头的多段，中英文混排还要在两个码表之间切换，
再加上状态报告、有效期、号码的半字节编码。这个库把这些都做完，
并且保证解码再编码后与原报文逐字节一致——对接运营商网关时这一点很关键，
差一个字节就会被判为非法报文。

## 安装

```bash
moon add chen333w/moon-sms-pdu
```

## 用法

解析一条从串口读到的 PDU：

```moonbit
let pdu = @lib.parse_pdu("07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07")
match pdu {
  Deliver(deliver) => {
    println(deliver.originating.to_string_display())  // +31641600986
    println(deliver.text)                             // How are you?
    println(deliver.timestamp.to_display())           // 2002-08-26T19:37:41+00:00
  }
  _ => ()
}
```

组装一条要发出去的短信：

```moonbit
let submit = @lib.SmsSubmit::new(
  Number(International, Isdn, "8613800138000"),
  "Hello",
)
println(@lib.Pdu::Submit(submit).to_hex())
```

长短信会被切成多段，每段带同一个参考号和序号：

```moonbit
let parts = @lib.build_submits(destination, long_text, reference=42)
for submit in parts {
  send_over_at_command(@lib.Pdu::Submit(submit).to_hex())
}
```

收到的分段短信按参考号重新拼起来：

```moonbit
// 分段可以乱序、可以重复，缺片时返回 None
println(@lib.assemble(delivered_parts))
```

## 命令行

```bash
moon run cmd/main -- decode 07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07
moon run cmd/main -- encode '+8613800138000' 'Hello from MoonBit'
moon run cmd/main -- parts  '+8613800138000' "$(cat long_message.txt)"
moon run cmd/main -- length '一条比较长的短信……'
```

`decode` 会顺带打印重编码后的十六进制，方便直接比对报文。

## 实现范围

编码：

- GSM 03.38 默认字符表，含 0x1B 转义表（`€` `[` `]` `{` `}` `\` `~` `|` `^`）
- septet 打包与解包，支持任意比特偏移，所以 UDH 和正文可以共用一条比特流
- UCS-2，代理对按 UTF-16BE 拆成两字节
- 8-bit 原始数据，供 OTA、WAP Push 一类业务使用

PDU：

- SMS-SUBMIT、SMS-DELIVER、SMS-STATUS-REPORT 三个方向的编解码
- SMSC 地址前缀，BCD 半字节顺序按 23.040 §9.1.2.5
- 数字地址与字母数字地址（发件人是名字的情况）
- TP-DCS 的字符集判定，含压缩位、消息类别位
- 相对有效期（分钟/天/周三档）与绝对有效期
- 用户数据头：分段、端口寻址
- 分段消息的切分与重组

## 几个容易踩的坑

这些坑都是实际调试时撞到的，写在这里省得别人再撞一次。

**时间戳的年份从 1900 起算。** 23.040 里 TP-SCTS 存的是相对 1900 的偏移。
如果换成 2000，年份会整体差 100 年，而且只在报文里看不出来。

**时区字节要原样保留。** 时区放在半字节里，符号位是 bit 3。
负数零（`0x08`）和正零（`0x00`）在语义上都表示 UTC，
但如果解码时把它归一化成整数分钟，再编码就会把 `0x08` 写成 `0x00`。
所以库里存的是原始字节，不是偏移量。

**带 UDH 时 TP-UDL 的单位是混的。** 头部的长度按八位组算，
后面的正文按 septet 算。把两者当成同一单位处理，长短信就会解出乱码或者越界。

**0x40 在不同 PDU 里含义不同。** SUBMIT 里它是 TP-UDHI（有无用户数据头），
DELIVER 里同样是 UDHI，但 DELIVER 的 bit 5 是 TP-SRI（要求状态报告），
不能混。这个错误的表现是：一条本该正常的短信被当成带头的，正文整体错位。

**UCS-2 的容量单位是八位组。** 单条 140 字节、分段 134 字节，换算成字符是 70 和 67。
如果按字符数限制长度，中文短信用到一半就会被截断。

## 测试

```bash
moon test
```

测试里用了几个真实报文做端到端校验，包括：

- 一份 3GPP 文档里的荷兰运营商短信
- 中英文混排的往返
- 三段的英文长短信，每段编码-解码-再编码后与原报文逐字节相同
- UUID 分段头与端口寻址
- 畸形输入必须抛错而不是崩溃

## 许可

Apache-2.0