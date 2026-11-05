# moon-sms-pdu

SMS PDU 编解码，纯 MoonBit，无 FFI，无 C 依赖。

## 安装

```bash
moon add chen333w/moon-sms-pdu
```

## 用法

解析一条 PDU：

```moonbit nocheck
let pdu = @lib.parse_pdu("07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07")
match pdu {
  Deliver(deliver) => {
    println(deliver.originating.to_string_display())  // +31641600986
    println(deliver.text)                             // How are you?
    println(deliver.timestamp.to_display())           // 1902-08-26T19:37:41+00:00
  }
  _ => ()
}
```

组装一条 SMS-SUBMIT：

```moonbit nocheck
let submit = @lib.SmsSubmit::new(
  Number(International, Isdn, "8613800138000"),
  "Hello",
)
println(@lib.Pdu::Submit(submit).to_hex())
```

长短信切成多段，每段共用参考号：

```moonbit nocheck
let parts = @lib.build_submits(destination, long_text, reference=42)
for submit in parts {
  send_over_at_command(@lib.Pdu::Submit(submit).to_hex())
}
```

收到的分段按参考号重组。乱序和重复都能处理，缺片时返回 `None`：

```moonbit nocheck
println(@lib.assemble(delivered_parts))
```

USSD 走同一套传输，格式不同：

```moonbit nocheck
let ussd = @lib.UssdMessage::new("*100#")
println(@lib.octets_to_hex(ussd.to_octets()))
```

## 命令行

```bash
moon run cmd/main -- decode 07911326040000F0040B911346610089F60000208062917314080CC8F71D14969741F977FD07
moon run cmd/main -- encode '+8613800138000' 'Hello from MoonBit'
moon run cmd/main -- parts  '+8613800138000' "$(cat long_message.txt)"
moon run cmd/main -- length '一条比较长的短信……'
moon run cmd/main -- ussd   '*100#'
```

`decode` 会打印重编码后的十六进制，可以直接和原报文对比。

## 支持范围

字符编码：

- GSM 03.38 默认字符表与 0x1B 转义表（`€` `[` `]` `{` `}` `\` `~` `|` `^`）
- septet 打包与解包，支持任意比特偏移，UDH 和正文可共用一条比特流
- UCS-2，代理对按 UTF-16BE 拆成两个码元
- 8-bit 原始数据，用于 OTA、WAP Push

PDU：

- SMS-SUBMIT、SMS-DELIVER、SMS-STATUS-REPORT 编解码
- SMSC 地址前缀，BCD 半字节顺序按 23.040 §9.1.2.5
- 数字地址与字母数字地址
- TP-DCS 字符集、压缩标志、消息类别（含 class 0 闪信）、语音信箱指示
- 相对有效期（分钟/天/周三档）与绝对有效期
- 用户数据头：分段、端口寻址
- 分段消息的切分与重组

不支持 SMS-COMMAND（TPDU 类型 10 且 bit 1 为 0），解析时抛错。

## 解码时的几处约定

**TP-SCTS 的年份相对 1900。** 按 2000 算是错的，会让所有时间戳差 100 年。
文中示例报文解出 1902 年，是原报文本身如此。

**时区保存原始字节，不存偏移量。** 符号位在 bit 3，`0x08` 是负零。
归一化成整数分钟再写回会变成 `0x00`，逐字节比对就对不上了。

**带 UDH 时 TP-UDL 的单位不同。** 头部长度按八位组，正文按 septet。
两者混用会导致越界或解出乱码。

**bit 0x40 在不同 TPDU 里含义不同。** SUBMIT 和 DELIVER 里都是 TP-UDHI，
但 DELIVER 的 bit 5 是 TP-SRI。误判会把普通短信当成带头的，正文整体错位。

**UCS-2 的容量按八位组算。** 单条 140 字节、分段 134 字节，折合 70 和 67 个字符。
按字符数限长会把中文短信截断。

**未定义的转义字符原样返回。** 0x1B 后面跟的码在扩展表里没有时，
回退到默认表对应位置，不丢弃。

## 测试

```bash
moon test
```

40 个测试，覆盖：

- 3GPP 文档中的荷兰运营商短信样本
- 中英文混排往返
- 三段英文长短信，逐段编码-解码-再编码后与原报文完全一致
- 分段头、端口寻址、字母数字发件人、8-bit 载荷
- 消息类别、压缩标志、语音信箱指示
- 畸形输入必须抛错

## 许可

Apache-2.0