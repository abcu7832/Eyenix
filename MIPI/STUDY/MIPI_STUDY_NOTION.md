# MIPI STUDY

> 💡 **MIPI RX** — D-PHY only, CSI-2

---

## PHY ↔ CSI-2 신호

| Symbol | Dir | 설명 |
| --- | --- | --- |
| RxByteClkHS[4] | I | HS 수신 Byte Clock. 수신된 HS DDR 클럭을 분주해서 생성 |
| RxDataHS[4][7:0] | I | HS 수신 데이터, RxDataHS[0]이 먼저 수신됨. RxByteClkHS 상승 엣지 기준 |
| RxValidHS[4] | I | HS 수신 데이터 유효 |
| RxActiveHS[4] | I | HS 수신 활성 상태 |
| RxSyncHS[4] | I | HS 수신 동기화 관측됨. HS 전송 시작 시 1 사이클 간 High |
| ErrSotHS[4] | I | SoT Soft Error. SoT 시퀀스가 손상되었으나 동기화는 가능한 경우 |
| ErrSotSyncHS[4] | I | SoT 동기화 불가 에러. SoT 시퀀스가 완전히 손상된 경우 |
| ErrControl[4] | I | 잘못된 상태 시퀀스 감지 시 에러 |
| Stopstate[4] | I | Lane이 Stop 상태임을 표시 (LP-11) |
| Enable[4] | O | Lane Module 활성화. Low 시 모든 드라이버/터미네이터/불량 감지기 OFF |
| ForceRxmode[4] | O | Lane Module을 강제로 Rx 모드 / Stop 대기 상태로 전환 |

---

## ROADMAP

### PPI 데이터 폭 — 8b/lane 유지 또는 기어링 적용

기어링 적용 이유: 내부 로직의 클럭을 낮추기 위함
기어링 → 내부 데이터 버스를 8b가 아닌 16b, 32b로 확장하여 사용하는거.
⇒ 기어링을 많이 적용할수록 합성도 수월하고 전력, PnR도 수월해짐. but 면적 증가
⇒ 14nm에서 필요한가? 타이밍 클로징 관점보다는 전력으로 관점 변경됨. + PnR 이슈 발생 가능

SW구현: 일단 파라미터화 설계

### PHY가 레인 정렬을 어디까지 해주는지 먼저 확인

: UI 이내까지 정렬 (D-PHY SPEC)

1. **D-PHY 내에 skew calibration이 구현된 경우**
   특정 시기마다 패턴 발생기에서 각 레인마다 동일한 비트 패턴을 보내고 정해진 패턴이 들어왔는지 레인별로 인식한 뒤 레인별 도착 시점 차이를 디지털 값으로 환산하고 측정된 skew 값을 저장.
   레인 간 skew 차이가 UI 단위(bit 전송 단위) 이내가 될 때까지 줄임.
   → lane align(align buffer)의 역할: UI 단위 이하의 오차까지도 잡기 위함.
   ⇒ d-phy spec Figure 25
   RxSyncHS가 정확히 같은 BYTECLK에 발생했는지 확인 → 어긋나 있으면 레인별 버퍼로 싱크 맞춤.

2. **구현 X**
   d-phy 내 skew calibration 없이 csi-2로 데이터를 넘긴다면, 배선 문제로 인한 lane간 (skew)가 발생할 가능성이 있음 → align buffer 필요 → 각 lane이 동일한 주파수로 들어오지만 위상은 미세하게 다를 수 있음. → 데이터 레인마다 바라보는 클럭이 달라짐 → async fifo 필요

최대 10Gbps → 2.5Gbps/lane → 합성: (BYTE) 312.5 MHz

### SoT 에러 두 종류의 처리 정책 구분

#### SoT 에러 두 종류

> 💡 **SoT 패턴**
> 사실 **"1비트 에러까지는 허용"이라는 명시적 규정**이 있음
> 정확히는 "1비트 에러 ⇒ Soft, 그 이상/패턴 자체를 못 알아볼 정도 ⇒ Hard"에 가까움

- 정상
- SoT 에러
  > 💡 ErrSotHS: 성공하긴 했는데 그 과정(리더 구간)이 이상적이지 않았다는 걸 알리는 신호
- SoT Sync 에러
  > 💡 ErrSotSyncHS → ON: 일정 기간 동안(THS-SETTLE) SoT 패턴을 찾지 못하는 경우

LP11 → LP01 → LP00 → HS-0 → SoT (Sync word Detection) → Payload → EoT

| Signal | 내용 |
| --- | --- |
| ErrSotHS | SoT 패턴 1 bit 이상 but 검출 → 동기화 성공 → RxSyncHS와 함께 pulse |
| ErrSotSyncHS | SoT 패턴 매우 이상 → 동기화 실패 → pulse |

> 💡 ErrSotHS ON → 페이로드 전달
> ErrSotSyncHS ON → 페이로드 전달 X
>
> **스펙 권장 정책**
>
> | 에러 | 스펙의 공식 권장 처리 |
> | --- | --- |
> | ErrSotHS | Application Layer로 전달. 에러가 검출되고 정정되었으며 동기화 메커니즘 자체는 영향 X |
> | ErrSotSyncHS | Protocol Decoding Level, Application Layer로 전달. 이 에러가 발생하면 다음 LP-11이 등장할때까지 데이터 무시. |
> | ErrControl | Application Layer로 전달. |
>
> ErrSotHS 발생 → 신뢰도 낮다는 태그 붙임, 데이터는 유지
>
> ErrSotSyncHS 발생 → PHY 레벨 뿐만 아니라 프레임 레벨에서도 에러를 유발시켜야 한다. ⇒ 이 프레임은 유효하지 않음. → 프레임을 버린다. (Annex C.2/C.4)
> or ErrSotSyncHS가 발생한 line을 비워두고 페이로드를 받는다. 앞이나 뒤의 같은 짝 홀 라인(bayer pattern)을 임시로 라인 버퍼에 저장하고 문제가 되는 순간의 프레임 버퍼에 write한다. or 이전 프레임의 같은 라인으로 대체 or 결손 라인을 0으로 채워넣고 ISP에서 별도로 처리(Claude)

---

## CSI-2

### [Terminology]

**Lane**
- 단방향(Unidirectional), 포인트-투-포인트 방식의 **2선 또는 3선 인터페이스**
- 고속 직렬 클럭 또는 데이터 전송에 사용
- 사용하는 PHY 규격에 따라 와이어 수 결정
  - **D-PHY**: 1개의 Clock Lane + 1개 이상의 Data Lane으로 구성
  - **C-PHY**: 1개 이상의 Lane으로 구성, 각 Lane이 클럭과 데이터를 동시에 전송
- D-PHY와 C-PHY 공통 기술 시, *Data Lane* 이라는 용어를 혼용하기도 함

**Packet**
- 인터페이스를 통해 데이터를 전송하기 위해 정해진 형식으로 구성된 Byte 그룹
- **Byte**가 패킷을 구성하는 기본 단위

**Payload**
- 동기화 정보, 헤더, ECC, CRC 등 프로토콜 관련 정보를 모두 제거한 순수 데이터
- Application Processor와 Peripheral 간 전송의 핵심 데이터

**Sleep Mode (SLM)**
- **누설 전류 수준의 전력만 소비**하는 최저 전력 소비 모드

**Transmission**
- 고속 직렬 데이터가 버스를 통해 **활발히 전송되는 시간**
- 1개 이상의 패킷으로 구성
- **SoT(Start of Transmission)** 으로 시작, **EoT(End of Transmission)** 으로 종료

**Virtual Channel**
- 최대 **4개의 독립적인 데이터 스트림**을 지원
- 각 Peripheral의 데이터 스트림이 하나의 Virtual Channel을 구성
- 여러 스트림을 **인터리빙(Interleaving)** 하여 순차적 패킷으로 전송 가능
- 각 패킷은 특정 Peripheral 또는 채널에 연결되는 정보를 포함

#### General

| 약어 | 풀네임 |
| --- | --- |
| BER | Bit Error Rate |
| CCI | Camera Control Interface |
| CIL | Control and Interface Logic |
| CRC | Cyclic Redundancy Check |
| CSI | Camera Serial Interface |
| CSPS | Chroma Shifted Pixel Sampling |
| DDR | Dual Data Rate |
| ECC | Error Correction Code |
| EXIF | Exchangeable Image File Format |

#### Interface & Protocol

| 약어 | 풀네임 | 설명 |
| --- | --- | --- |
| DI | Data Identifier | 패킷의 Virtual Channel과 Data Type을 합친 1바이트 식별자 |
| DT | Data Type | 패킷에 담긴 데이터의 종류 (RAW8, YUV422, RGB888 등) |
| LLP | Low Level Protocol | PHY 바로 위의 저수준 프로토콜 계층. 패킷 구성 및 전송 규칙 정의 |
| PF | Packet Footer | 패킷 끝부분. CRC |
| PH | Packet Header | 패킷 앞부분. DI(Data Identifier), WC(Word Count), ECC 포함 |
| PI | Packet Identifier | 패킷의 종류를 구분하는 식별자 (Short/Long Packet 등) |
| PT | Packet Type | 패킷의 유형 분류 (Data Packet, Sync Packet 등) |
| PPI | PHY Protocol Interface | PHY와 상위 프로토콜 계층 간의 인터페이스 |
| PHY | Physical Layer | 물리 계층. 실제 신호를 전기적으로 송수신하는 최하위 계층 |

#### Operation Mode

| 약어 | 풀네임 | 설명 |
| --- | --- | --- |
| HS | High Speed (OP mode) | 고속 데이터 전송 모드. 차동 신호 방식, 대용량 데이터 전송 |
| HS-RX | High-Speed Receiver | HS 모드로 데이터를 **수신**하는 회로 블록 |
| HS-TX | High-Speed Transmitter | HS 모드로 데이터를 **송신**하는 회로 블록 |
| LP | Low-Power (OP mode) | 저전력 동작 모드. 제어 신호 또는 대기 상태에 사용 |
| LP-RX | Low-Power Receiver | LP 모드로 신호를 **수신**하는 회로, Large-Swing Single-Ended |
| LP-TX | Low-Power Transmitter | LP 모드로 신호를 **송신**하는 회로, Large-Swing Single-Ended |
| SLM | Sleep Mode | 누설 전류 수준의 전력만 소비하는 최저 전력 상태 |
| ULPS | Ultra Low Power State | LP보다 더 낮은 초저전력 상태. Lane 비활성화 → 전력 소비 최소화 |

📢 Large-Swing Single-Ended: LP 모드에서 사용하는 신호 방식으로, HS의 차동 방식과 달리 단일 선로에서 0V / 1.2V 사이의 큰 전압 스윙으로 신호를 전달. 속도는 느리지만 회로가 단순하고 전력 소비가 낮음.

#### Signal & Transmission

| 약어 | 풀네임 |
| --- | --- |
| EoT | End of Transmission |
| SoT | Start of Transmission |
| FE | Frame End |
| FS | Frame Start |
| LE | Line End |
| LS | Line Start |
| LSB | Least Significant Bit |
| LSS | Least Significant Symbol |
| MSB | Most Significant Bit |
| MSS | Most Significant Symbol |
| RX | Receiver |
| TX | Transmitter |

#### Communication Interface

| 약어 | 풀네임 |
| --- | --- |
| I2C | Inter-Integrated Circuit |
| SCL | Serial Clock (for CCI) |
| SDA | Serial Data (for CCI) |

#### Color & Video Format

| 약어 | 풀네임 |
| --- | --- |
| JFIF | JPEG File Interchange Format |
| JPEG | Joint Photographic Expert Group |
| RGB | Color representation |
| VGA | Video Graphics Array |
| YUV | Color representation |

### [CSI-2 Layer Definitions]

PHY → Lane Management → Low Level Protocol → Application

| 계층 | 내용 | 상세 |
| --- | --- | --- |
| PHY | 물리 계층 | [Physical Layer] |
| Lane Management | 레인 관리 | [Lane Management] |
| Low Level Protocol | 패킷 | [Low Level Protocol] |
| Application | 응용 | |

### [Physical Layer]

D-PHY: 차동 신호(선: 2개)를 가지고 데이터 레인, 클럭 레인으로 구성됨.

```
# Clock Lane
HS mode -> continuous clock, 데이터 패킷 전송 중의 클럭
LP-11에 진입 -> non-continuous clock, 클럭 x

# Data Lane
더 높은 date rate를 위해 여러 개의 레인 사용
-> 배선 길이 차이에 의한 레인 간의 deskew 필요 -> Calibration
cf) Calibration: deskew sequence pattern Tx가 Rx에 전송 -> Rx 패턴 감지 -> 튜닝
```

### [Lane Management]

**Lane Alignment**
Lane 별 데이터 동기화

**Multi-Lane Distribution and Merging**
Multi-Lane(Data Lane): 더 높은 대역폭을 위함.
Distribution → Tx에 대한 내용
Merging → Rx에 대한 내용 ⇒ Lane Merging Function (LMF)

```
# Concept
## Single-Lane
Lane 1 -> SerDes -> BYTEs -> Lane Align -> LMF -> [Byte2Pixel Unpacking]

## Multi-Lane
### Lane 개수에 맞게 나눠지는 경우
-> 모든 레인 데이터 수신 동시 종료

### Lane 개수에 맞게 나눠지지 않는 경우
-> 모든 레인 데이터 수신 동시 종료x

cf) Multi-Lane 사용할때, CCI로 데이터 레인 개수 조정 가능.
```

### [Low Level Protocol]

Byte 단위, Short & Long Packet

```
# Low Level Protocol Packet Overview

PH-DATA-PF => Long Packet
DATA: Word Count(WC)만큼 존재
SP => Short Packet: Data ID - 2-Byte Short Packet Data field - VCX + ECC
ex) Short Packet
if Data Type is Frame Synchronization, Short Packet Data field is frame number
if Data Type is Line Synchronization, Short Packet Data field is line number

ST: Start of Transmission cf) HS-0 SoT Pattern (1 Byte)
ET: End of Transmission
LPS: Low Power State cf) LP-11
PH: Packet Header cf) ECC[31:24], WC[23:8], DI[7:0]
PF: Packet Footer + Filler(option) cf) 16-bit, CRC/Checksum

## Ex1 -> 어떤 시퀀스로 진행할지는 센서마다 차이가 있음.
LPS -> SoT -> FS(short) -> LS(short) -> LineData1(long) -> LE -> LS -> 
LineData2 -> LE -> ... -> LineDataN -> LE -> FE -> EoT -> LPS

## Ex2
FS
LS Packet LE
LS Packet LE
...
LS Packet LE
FE
cf) Blank 구간은 payload 전송x -> LPS를 관찰해서 Line, Frame Blanking을 관찰함.
```

```
DI: Data Identifier VC[7:6], DT[5:0]
VC: Virtual Channel
cf) Virtual Channel Identifier
Packet In -> 채널 감지 -> Logical Channel Control (4:1 MUX) -> 해당 채널
cf) 채널마다 다른 타입 데이터 송수신 가능
```

| DT | Description |
| --- | --- |
| 0x00 to 0x07 | 동기화 SP Data Types |
| 0x08 to 0x0F | Short Packet Data Types |
| 0x10 to 0x17 | Long Packet Data Types |
| 0x18 to 0x1F | YUV Data |
| 0x20 to 0x26 | RGB Data |
| 0x27 to 0x2F | RAW Data |
| 0x30 to 0x37 | User Defined Byte-based Data |
| 0x38 | USL Commands |
| 0x39 to 0x3E | Reserved |

| DT | Description |
| --- | --- |
| 0x00 | Frame Start |
| 0x01 | Frame End |
| 0x02 | Line Start |
| 0x03 | Line Start |
| 0x04 | End of Transmission |
| 0x05~0x07 | Reserved |

```
# Packet Header Error Correction Code for D-PHY Physical Layer
## 6-bit Parity Generator
input: 패킷 헤더의 DI, WC, VC -> 26-bit
output: ECC -> 6-bit
cf) d + p + 1 ≤ 2^p, p: 만족하는 p의 최솟값, d: ECC 제외 나머지 비트

## 일반 Hamming code (수식: G = [I|A])
데이터 비트를 행렬 G에 곱해서 Hamming code word (벡터 형태)
-> Hamming code word: 기존 데이터 비트와 계산된 패리티 비트로 구성
-> 행렬 G: Identity 행렬(I)과 패리티 생성 행렬(A)로 구성됨.
cf) 비트들의 연속을 벡터로 보기!!
cf) PH = p*G -> [1x32] == [1x26] x [26x32]
cf) 행렬 A : [kx(n-k)] => [26x6]

## Hamming-Modified Code -> 6-bit ECC 주로 사용
연산 과정에서 1bit 추가 (XOR로 1인 비트가 홀수개인지 짝수개인지 확인용)

## Hamming Code의 잠재적 위험?
if 데이터 비트는 멀쩡 & 수신받아서 계산한 검증 결과와 송신된 ECC(Tx로부터 송신된 ECC
에 에러가 발생하여 비트가 틀어짐)가 다른 경우, 잘못된 flip이 발생할 수 있음.
-> 보조 수단으로 사용되어야함.

============================================================================
# 26-bit ECC on RX Side Including Error Correction
input: 32-bit Packet Header from Tx {Byte2,1,0_i,VCX[2],ECC_R[6]}
---------------------------------------------------
Byte2,1,0_i,VCX[2]->[6-bit Parity Generator]->ECC_C[6]
ECC_R[6]^ECC_C[6]=SYN[6]
SYN[6]->[6-bit Syndrome Decoder]->Error Message&corrected Byte2,1,0,VCX[2]
Byte2,1,0_i^corrected Byte2,1,0->Byte2,1,0,VCX2
---------------------------------------------------
output: ECC를 제외한 나머지 26-bit Packet Header
cf) VCX[2]=2'b00
```

```
# Checksum Generation
2-Byte Packet Footer(PF) of long packet

## POLYNOMINAL: x^16+x^12+x^5+x^0 -> 0x1021
### LSB부터 처리
POLY: 0x1021 =(비트순서 거꾸로)> 0x8408
### MSB부터 처리
POLY: 0x1021

## 연산
input:crc(0xffff),WC,PAYLOAD_1~WC
---------------------------------------------------
PAYLOAD_1~WC BYTE (WC회 반복)
-----
PAYLOAD bit width 만큼 반복 -> 8회
crc = (crc[0]!=PAYLOAD[0]) ? ((crc >> 1) ^ POLY) : (crc >> 1);
PAYLOAD = PAYLOAD >> 1;
------
---------------------------------------------------
output: 한 라인에 대한 페이로드 전체의 crc[15:0] 결과

# 비교
수신된 crc, 계산한 crc가 동일하면, 정상
수신된 crc, 계산한 crc가 다르면, 비정상

cf) 디버깅
crc 에러발생 -> 어느 라인에서 발생했는지 기록
```

```
# Option 요소
## Latency Reduction and Transport Efficiency (LRTE)
	Latency 감소 & 전송 효율 여러 가지 개선 방안 제시
	1. Interpacket Latency Reduction (ILR)
		EoT, LPS, SoT 시퀀스를 간단하게 대체(EPD)하자
	2. ILR & 향상된 전송 효율 함께 사용
	
## Unified Serial Link (USL)
	CCI를 대체해서 wire의 수를 줄이자!
	PHY에서 양방향 통신도 지원해야함.

## Data Scrambling 
	목적: 전자기 간섭(EMI), RF 자기간섭 완화
	Tx에서 Scrambling 적용된 신호가 송신되어야함. -> 확인 필요
	-> Tx에서 적용가능하다면 De-Scrambling 블록 구현 필요(lane merge 앞단)

### 연산
input: Long Packet, Short Packet
---------------------------------------------------
Polynomial이 적용된 Linear Feedback Shift Register (LFSR) 블록
Polynomial = x^16+x^5+x^4+x^3+x^0 
cf) 초기화: 각 레인에 할당된 16-bit 씨드값

LFSR 블록 내 16개 D-F/F: PRBS Register -> 상위 2-Byte를 뒤집은거 
=> PRBS Byte Capture & Modulo-2 Sum 블록 8개 D-F/F -> PRBS Byte

ScrambledData = input ^ PRBS
---------------------------------------------------
output: 랜덤하게 보이는 비트들의 연속 -> 효과: 물리적 간섭 완화

## Smart Region of Interest (SROI)

## Packet Data Payload Size Rules

## Frame Format Examples

## Data Interleaving 
같은 영상 데이터 스트림 내에서 다른 포맷 데이터를 전송하는 방법
```

### [Annex B CSI-2 Implementation Example]

| 블록 | 역할 |
| --- | --- |
| Lane Merger | 각 데이터 레인의 RxDataHS을 FIFO로 담아서 패킷의 Byte을 Protocol로 전달 |
| CSI2 Protocol | ECC 헤더 보정 → payload → CRC 에러 감지 및 알림 |
| Application | 정책 (에러, 프레임, 라인 etc) |

```
# PHY delay FIFO -> Shift Register 느낌이 아님!!
역할: 레인 간 skew 차이를 극복하기 위한 수단
속성: asycn fifo (write domain: phy로부터 들어오는 RxByteClkHS, read domain: 각
 레인 중 기준 레인의 RxByteClkHS)
 
# Lane merger control logic
감시 대상: phy로부터 들어오는 상태 신호

## 결정 사항
1. FIFO의 write enable
2. FIFO를 언제 read 할지
cf) 에러 상태 신호는 Protocol Layer로 전달

# RxDataHS[7:0]의 흐름
1. 각 레인의 데이터를 비동기 FIFO를 이용해서 하나의 클럭으로 동기화하고 skew 해결
2. Lane merger control logic의 제어에 따라 비동기 FIFO에서 데이터를 read하고 
	Protocol Layer로 전달
```

### [Annex C CSI-2 Recommended Receiver Error Behavior]

cf) Debug Point

**D-PHY Level Error**
- ErrSotHS → 페이로드 수신 → Application level에 알림
- ErrSotSyncHS → 페이로드 폐기 → Protocol level에 알림 → 해당 패킷 수신 중단 → Stop State
- ErrControl → Application level에 알림

**Packet Level Error**
- ECC(Packet Header) 에러 (1-bit: 정정, 2-bit: 정정 불가 → 패킷 전체 폐기)
- CRC(Payload) 에러

**Protocol Decoding Level Error**
- ErrFrameSync → Application level에 알림
- ErrFrameData → Application level에 알림

### [Annex D CSI-2 Sleep Mode]

목적: 낭비되는 전력 최소화

방법: LP-11에서 CCI or 추가 시퀀스 or 트리거 신호를 통해 ULPS 상태로 전환 → LP-00

ULPS에서 벗어나기 → EXIT 시퀀스 → LP-11

---

## D-PHY

### [Terminology]

| 용어 | 정의 |
| --- | --- |
| DDR Clock | 이중 엣지(dual-edged) 데이터 전송에 사용되는 절반 속도(half rate) 클록 |
| Escape Mode | Data Lane에서 저속 명령 및 데이터를 매우 낮은 전력으로 전송할 수 있는 선택적 동작 모드 |
| Lane Interconnect | 차동(differential) High-Speed 신호와 Low-Power 단일 종단(single-ended) 신호 모두에 사용되는 2선 point-to-point 인터커넥트 |
| Lane Module | Lane 양쪽에서 신호를 구동 및/또는 수신하기 위한 모듈 |
| Link | 하나의 Clock Lane과 최소 하나 이상의 Data Lane을 포함하는 두 장치 간의 연결. 최소 2개의 PHY와 2개의 Lane Interconnect로 구성 |
| PHY Adapter | APPI의 심볼을 특정 PHY PPI에서 사용하는 신호로 변환하는 프로토콜 계층 |
| PHY Configuration | 가능한 Link를 나타내는 Lane들의 집합. 최소 2개의 Lane(하나의 Clock Lane과 하나 이상의 Data Lane)으로 구성 |
| Turnaround | Data Lane에서 통신 방향을 전환하는 것 |

| 약어 | 전체 명칭 |
| --- | --- |
| APPI | Abstracted PHY-Protocol Interface |
| BER | Bit Error Rate |
| CIL | Control and Interface Logic |
| DDR | Double Data Rate |
| EMI | Electro Magnetic Interference |
| EoT | End of Transmission |
| HS-RX | High-Speed Receiver (Low-Swing Differential) |
| HS-TX | High-Speed Transmitter (Low-Swing Differential) |
| ISTO | Industry Standards and Technology Organization |
| LP-CD | Low-Power Contention Detector |
| LPDT | Low-Power Data Transmission |
| LP-RX | Low-Power Receiver (Large-Swing Single-Ended) |
| LP-TX | Low-Power Transmitter (Large-Swing Single-Ended) |
| LPS | Low-Power State(s) |
| Mbps | Megabits per second |
| PLL | Phase-Locked Loop |
| PPI | PHY-Protocol Interface |
| RF | Radio Frequency |
| SE | Single-Ended |
| SoT | Start of Transmission |
| TLIS | Transmission-Line Interconnect Structure: Master와 Slave 사이의 물리적 인터커넥트 구현 |
| UI | Unit Interval, Clock Lane의 모든 HS 상태 지속 시간과 동일 |
| ULPS | Ultra-Low Power State |

### [Overview]

```
# SPEC
## 속도
HS: 80~1500 Mbps/lane (deskew calibration X), 최대 2.5Gbps
LP: 최대 10Mbps
=> 1.5Gbps/lane 이상 -> deskew calibration 필수

cf) 최대 bitrate는 설계(Tx,Rx,배선)에 따라 달라짐.

## 구조
2-wire/lane
HS -> Terminated Resistor O -> 빠른 신호 변이를 위함
=> LP는 필요없지만, EMI 대응을 위해 LP 드라이버는 slew-rate 제어 및 전류 제한 필요

### Lane Modules
LP: Large swing (1.2V)
HS: Low Voltage swing (0.2V)

### Clock Generation
클럭은 PHY 외부에서 생성됨.
```

### [Sequence]

*(이미지 3장 첨부 위치)*

**Requests**

| Request | LP sequence |
| --- | --- |
| HS entry | LP-11 -> LP-01 -> LP-00 |
| Escape | LP-11 -> LP-10 -> LP-00 -> LP-01 -> LP-00 |
| ~~Turnaround~~ | LP-11 -> LP-10 -> LP-00 -> LP-10 -> LP-00 |

**High-Speed Data Transmission**

```
# Start-of-Transmission
(Tx) Drives Stop state (LP-11)
(Rx) Observes Stop state
(Tx) Drives HS-Rqst state (LP-01) for time T_LPX
(Rx) Observes transition from LP-11 to LP-01 on the Lines
(Tx) Drives Bridge state (LP-00) for time THS-PREPARE
(Rx) Observes transition from LP-01 to LP-00 on the Lines, enables Line Termination after time TD-TERM-EN
(Tx) Enables High-Speed driver and disables Low-Power drivers simultaneously.
(Tx) Drives HS-0 for a time THS-ZERO
(Rx) Enables HS-RX and waits for timer THS-SETTLE to expire in order to neglect transition effects
(Rx) Starts looking for Leader-Sequence
(Tx) Inserts the HS Sync-Sequence '00011101' beginning on a rising Clock edge
(Rx) Synchronizes upon recognition of Leader Sequence '011101'
(Tx) Continues to Transmit High-Speed payload data
(Rx) Receives payload data

# End-of-Transmission
(Tx) Completes Transmission of payload data
(Rx) Receives payload data
(Tx) 마지막 페이로드 비트 후에 곧바로 차동 신호를 반전시키고, THS-TRAIL동안 그 상태 유지
(Tx) Disables the HS-TX, enables the LP-TX, and drives Stop state (LP-11) for a time THS-EXIT
(Rx) Detects the Lines leaving LP-00 state and entering Stop state (LP-11) and disables Termination
(Rx) Neglect bits of last period THS-SKIP to hide transition effects
(Rx) Detect last transition in valid Data, determine last valid Data byte and skip trailer sequence
```

```
# HS모드에서 클럭 레인과 데이터 레인 간의 시퀀스
(Start) 먼저 클럭 레인부터 클럭 전송 후, 페이로드 전송
(End) 먼저 페이로드 전송 완료 후, 클럭 레인 EoT 시퀀
```

**Escape**
- Remote Triggers ex) Reset Trigger
- Low-Power Data Transmission → 주로 DSI에서 사용, CSI-2 생략 가능?
- Ultra-Low Power State

**Initialization**

```
1. 시스템/PPI 신호 → Master Init 시작 (Master Off → Master Init)
2. Master가 라인에 Stop 상태(LP-11)를 T_{INIT,MASTER} 이상 유지 (TX-Stop)
   ※ 이 구간 전까지 Slave는 라인 상태를 그냥 무시함
3. Slave가 Master의 Stop 상태를 감시하기 시작
4. T_{INIT,SLAVE} 만큼 감시가 지속되면 Slave도 초기화 완료 (Slave Init → RX-Stop)
```

### [Fault Detection]

**Contention Detection**

```
: D-PHY 레벨, 전기적 충돌 감지

## Contention
정상 동작 시 한 레인은 항상 한쪽(Master or Slave)에서만 구동되어야 하는데, 
오동작으로 양쪽에서 동시에 구동되거나 양쪽 다 구동 안 되는 상태가 되는 것.

양쪽 모두 LP 신호로 서로 반대 레벨을 구동
→ 라인 전압이 V_OL,MIN과 V_OH,MAX 사이 애매한 값으로 안정됨
→ V_IHCD 기준을 이용해 최소 한쪽은 반드시 감지 가능

한쪽은 LP-high, 다른 쪽은 HS-low를 구동
→ 전압이 V_IL보다 낮게 안정됨
→ LP-high를 보내던 쪽에서 감지됨
```

**Sequence Error Detection**

```
: D-PHY 레벨, 시퀀스 오류 감지

## 에러 종류
SoT Error: HS 시작 Leader 시퀀스에 1비트(또는 일부 멀티비트) 오류 발생 
→ 동기화는 됐지만 데이터 신뢰도는 낮음
SoT Sync Error: Leader 시퀀스가 너무 깨져서 동기화 자체가 불가능한 수준
EoT Sync Error: 전송 마지막 비트가 바이트 경계에 맞지 않음
(LP-11 감지 시 EoT 처리 중에만 발생 가능)
Escape Mode Entry Command Error: Escape 모드 진입 커맨드를 인식 못 함
LP Transmission Sync Error: LP 데이터 전송 끝에 바이트 경계 동기화 실패
False Control Error: LP-Rqst(LP-10) 뒤에 유효한 시퀀스가 안 이어지거나 
HS-Rqst 뒤에 Bridge State(LP-00)가 제대로 이어지지 않음

Leader 시퀀스: HS 전송이 시작될 때 가장 먼저 보내는 특수 비트 패턴
> 수신측에게 "지금부터 진짜 HS 데이터가 시작된다"는 것을 알리고, 
바이트 경계를 맞추기 위한 동기화 기준점
> 일부 Leader 시퀀스에 오류가 발생하더라도 충분히 유사함을 판별하는 로직을  
통해 Leader 시퀀스인지 판단가능함.
```

**Protocol Watch Timers**

```
: 프로토콜 레벨, 타임아웃 기반

> PHY만으로는 모든 결함 케이스를 잡을 수 없기 때문에, 
상위 프로토콜 레벨에서 타임아웃으로 최대 지속시간을 제한하는 보완 메커니즘

HS RX Timeout: HS 수신 중 일정 시간 안에 EoT가 안 오면 타임아웃
HS TX Timeout: HS 송신 최대 길이 제한
Escape Mode Timeout: Escape 모드 중 타임아웃, 상대측의 "Escape Silence Limit"보다 커야 함
Escape Mode Silence Timeout: LP TX-00 상태의 최대 길이 제한
```

- ~~Turnaround Error~~

### [하드웨어 배치 및 아날로그 설계]

**Interconnect and Lane Configuration**

```
# 하드웨어 배치
Lane -> Dp, Dn -> 배치 간격에 대한 규칙
너무 두 선이 너무 가까우면 HS에 좋음(EMI 방사 억제, 외부 노이즈에 강함),
but LP에 안 좋음(두 선 간에 서로 다른 전압으로 비대칭적 변화가 발생하면 상호 
간의 강한 커플링이 발생)
=> 제조하는데 오차가 발생하기 쉬움 -> 임피던스에 민감하게 반응
```

**Electrical Characteristics**

**High-Speed Data-Clock Timing**

```
HS Reference Clock (PHY 외부) -> [PLL] -> [Edge Detect Reg] -> DDR Clock
DDR Clock <-> Data signal 90도 위상차 => 안정적으로 데이터를 샘플링하기 위함
```

### [PHY-Protocol Interface]

```
# 위치
PHY Lane Module ←(PPI)→ Lane Alignment -> Lane Merge
```

#### PPI Signals

**High-Speed Transmit Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| TxDDRClkHS-I | I | MXXX, MCNN | Data Lane HS 송신용 DDR 클럭 (In-phase). 모든 Data Lane이 동일한 신호 공유 |
| TxDDRClkHS-Q | I | MCNN | Clock Lane HS 송신용 DDR 클럭. TxDDRClkHS-I 대비 위상 시프트(Quadrature)됨 |
| TxByteClkHS | O | MXXX, SRXX | HS 송신 Byte Clock. PPI 신호 동기화용. 주파수 = HS bit rate ÷ 8 |
| TxDataHS[7:0] | I | MXXX, SRXX | HS 송신 데이터(8비트). TxDataHS[0]이 먼저 전송됨. TxByteClkHS 상승 엣지에서 캡처 |
| TxRequestHS | I | MXXX, SRXX, MCNN | HS 송신 요청/데이터 유효 신호. Low→High: SoT 시작 / High→Low: EoT 시작 |
| TxReadyHS | O | MXXX, SRXX | HS 송신 준비 완료. TxByteClkHS 상승 엣지에서 유효 |
| TxSkewCalHS | I | MXXX | HS 송신 Skew 보정 트리거(옵션). Low→High: deskew burst 시작 / High→Low: 종료 |

**High-Speed Receive Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| RxByteClkHS | O | MRXX, SXXX | HS 수신 Byte Clock. 수신된 HS DDR 클럭을 분주해서 생성 |
| RxDataHS[7:0] | O | MRXX, SXXX | HS 수신 데이터(8비트). RxDataHS[0]이 먼저 수신됨. RxByteClkHS 상승 엣지 기준 전달 |
| RxValidHS | O | MRXX, SXXX | HS 수신 데이터 유효. RxReadyHS 없음 → 프로토콜은 매 상승 엣지마다 캡처해야 함 (throttle 불가) |
| RxActiveHS | O | MRXX, SXXX | HS 수신 활성 상태(수신 중임을 표시) |
| RxSyncHS | O | MRXX, SXXX | 수신 동기화 관측됨. HS 전송 시작 시 1 사이클간 High |
| RxClkActiveHS | O | SCNN | Clock Lane이 DDR 클럭을 수신 중임을 나타내는 비동기 신호 |
| RxDDRClkHS | O | SCNN | 수신된 DDR 클럭 자체 (RxClkActiveHS가 Low면 항상 Low) |
| RxSkewCalHS | O | SXXX | HS 수신 Skew 보정 관측(옵션). all-ones sync pattern 수신 시 Active |

**Escape Mode Transmit Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| TxClkEsc | I | MXXX, SXXY | Escape 시퀀스 생성용 클럭. LP 신호 위상 결정, D-PHY 스펙 6.6.2절 규정 |
| TxRequestEsc | I | MXXX, SXXY | Escape 모드 진입 요청. TxLpdtEsc/TxUlpsEsc/TxTriggerEsc 중 하나와 함께 어서트 |
| TxLpdtEsc | I | MXAX, SXXA | Escape 모드 LP 데이터 송신 진입 |
| TxUlpsExit | I | MXXX, SXXY, MCNN | ULP 상태 탈출 시퀀스 송신 트리거 |
| TxUlpsEsc | I | MXXX, SXXY | Escape 모드 ULP(Ultra-Low Power State) 진입 |
| TxTriggerEsc[3:0] | I | MXXX, SXXY | Escape 모드 Trigger 0~3 송신. 한 번에 하나만 어서트 가능 |
| TxDataEsc[7:0] | I | MXAX, SXXA | Escape 모드 LP 데이터(8비트). TxDataEsc[0] 먼저 전송, TxClkEsc 상승 엣지 캡처 |
| TxValidEsc | I | MXAX, SXXA | Escape 모드 송신 데이터 유효 |
| TxReadyEsc | O | MXAX, SXXA | Escape 모드 송신 준비 완료. TxClkEsc 상승 엣지 기준 유효 |

**Escape Mode Receive Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| RxClkEsc | O | MXXY, SXXX | Escape 모드 수신 데이터 전달용 클럭. 비동기적 특성으로 non-periodic일 수 있음 |
| RxLpdtEsc | O | MXXA, SXAX | Escape 모드 LP 데이터 수신 상태 |
| RxUlpsEsc | O | MXXY, SXXX | Escape 모드 ULP 수신 상태 |
| RxTriggerEsc[3:0] | O | MXXY, SXXX | Escape 모드 Trigger 수신 신호 |
| RxDataEsc[7:0] | O | MXAA, SXAX | Escape 모드 수신 데이터(8비트). RxClkEsc 상승 엣지 기준 전달 |
| RxValidEsc | O | MXAA, SXAX | Escape 모드 수신 데이터 유효 |

**Control Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| TurnRequest | I | XRXX, XFXY | Turn Around 요청. Tx 방향(Direction=0)일 때만 유효 |
| Direction | O | XRXX, XFXY | 현재 송수신 방향 표시 (0=Output/Tx, 1=Input/Rx) |
| TurnDisable | I | XRXX, XFXY | Turn-around 진입 방지(양방향 Lane이 단방향 모듈에 연결될 때 lock-up 방지용) |
| ForceRxmode | I | MRXX, MXXX, SXXX | Lane Module을 강제로 Rx 모드 / Stop 대기 상태로 전환 |
| ForceTxStopmode | I | MXXX, SRXX, SXXY | Lane Module을 강제로 Tx 모드 + Stop 상태로 전환 |
| Stopstate | O | XXXX, XCNN | Lane이 Stop 상태임을 표시 (LP-11) |
| Enable | I | XXXX, XCNN | Lane Module 활성화. Low 시 모든 드라이버/터미네이터/불량 감지기 OFF |
| TxUlpsClk | I | MCNN | Clock Lane의 ULP 상태 송신 트리거 |
| RxUlpsClkNot | O | SCNN | Clock Lane의 ULP 상태 수신 표시(active low) |
| UlpsActiveNot | O | XXXX, XCNN | ULP 상태(비활성) 표시 신호 (active low) |

**Error Signals**

| Symbol | Dir | Categories | 설명 |
| --- | --- | --- | --- |
| ErrSotHS | O | MRXX, SXXX | SoT Soft Error. HS-SYNC 시퀀스 손상, but 동기화 가능 |
| ErrSotSyncHS | O | MRXX, SXXX | SoT 동기화 불가 에러. HS-SYNC 시퀀스 완전히 손상 |
| ErrEsc | O | MXXY, SXXX | 인식 불가능한 Escape 진입 커맨드 수신 시 에러 |
| ErrSyncEsc | O | MXXA, SXAX | LP 데이터 송신 비트 수가 8의 배수가 아닐 때 에러 |
| ErrControl | O | MXXY, SXXX | 비정상적인 line state(LP) 조합 감지 시 에러 |
| ErrContentionLP0 | O | MXXY, SXXX | LP0 드라이브 중 충돌 감지 |
| ErrContentionLP1 | O | MXXY, SXXX | LP1 드라이브 중 충돌 감지 |

> 💡
> ```
> 정상 리더 시퀀스:  0 0 0 0 0 0 0 0 | 1 0 0 0 1 1 0 1 (=0xB8, Sync Word)
>                    └──HS-0 구간──┘  └────Sync Word────┘
>
> 손상된 경우:       0 0 1 0 0 1 0 0 | 1 0 0 0 1 1 0 1
>                    └─노이즈로 1 끼어듦─┘  └─Sync Word는 정상 도착─┘
> ```
> - **ErrSotHS**: HS-0 구간에 1(노이즈)가 끼어있지만, Sync Word는 손상되지 않은 경우
> - **ErrSotSyncHS**: HS-0 구간에 1(노이즈)가 끼어있어서, Sync Word가 손상된 경우
>   - Sync Word 패턴 아예 검출 안됨.
>   - 엉뚱한 타이밍에 패턴 검출

**PHY ↔ CSI-2 Signals** *(내용 없음)*

### [Skew Calibration]

```
# HS Skew Calibration On
동일한 TEST Pattern 레인별 전송 -> 레인별 수신 -> 비교 -> skew 확인 
-> 레인별 동기화 레지스터 계산 -> UI 이상의 skew 해결

## Detail
TEST Pattern 수신: 11111111_11111111_01010101 (T_SKEWCAL-SYNC + T_SKEWCAL 동안)
첫번째 negative edge를 가지고 skew를 판별함.
LP-11->LP-01->LP-00->HS-0->TEST->LP-11
```

---

## Debug Point

### CheckList

#### 디지털 에러 레지스터 변수 분리

1. **클럭 속도 단계적으로 낮추기** — 특정 속도 이하에서 에러가 사라진다면 마진 부족 문제
2. **레인수 줄여보기** — 에러가 멀티레인에서만 발생하고 싱글레인에서는 발생하지 않는다면 Lane merger or skew 문제
3. **해상도 / 프레임레이트 낮추기** — horizontal line이 짧아져도 재현 → 순간적 노이즈 / horizontal line이 긴 경우에만 재현 → 누적/드리프트성 문제
4. **환경 요인을 극단으로**

#### 관측 지점을 물리 계층으로 낮추기

1. **Logic Analyzer** — LP 상태 전이 캡처한 뒤, 에러 발생 직전 LP→HS 전환 타이밍이 스펙을 만족하는지 실측
2. **고속 오실로스코프** — eye diagram 확인: 각 레인의 신호 품질 확인

#### 시간/빈도 패턴 분석

1. 주기성이 있는가
2. 프레임 내 위치(몇 번째 라인, 라인 내 몇 번째 바이트)가 항상 비슷한지 확인 — 항상 같은 지점이면 결정론적 원인(특정 타이밍 경합, race condition), 랜덤이면 노이즈성 원인
3. 부팅 / 링크업 직후에만 몰리는지, 장시간 구동 후에 몰리는지 — 부팅/링크업 직후 → 초기화 시퀀스 문제 / 장시간 구동 이후 → 열화/드리프트 문제

#### 신호를 강제로 스트레스 주기 (Margin Test)

1. 마진을 깎아서 에러 발생 빈도를 인위적으로 높임 — 어떤 조건이 영향을 주는지 훨씬 찾을 수 있음
2. PCB 근처에 노이즈 소스를 켰다 껐다 하면서 상관관계 확인 → EMI 커플링 문제 여부 판단

#### 정상 레퍼런스와 비교

1. 같은 설계의 다른 보드에서도 동일하게 재현되는지 확인
2. 다른 Tx, 다른 Rx 조합으로 바꿔서 테스트

### 1. D-PHY PPI 레벨

| 에러 | 의미 |
| --- | --- |
| `ErrSotHS` | HS sync word에 일부 비트 에러가 있었지만 복구된 경우 (soft error) |
| `ErrSotSyncHS` | **"SoT 패턴 동기화 에러"** — sync word 정렬 자체가 실패해서 해당 packet 유실 |
| `ErrControl` | LP 모드 line state 시퀀스가 스펙에 정의된 조합이 아닌 경우 |

### 2. CSI-2 Protocol 레벨

| 에러 | 의미 |
| --- | --- |
| **ECC (1-bit) — 정정** | 헤더에 1bit 에러가 있었지만 정정. 데이터는 정상 사용 가능, "에러가 있었다"는 걸 알려주는 플래그 |
| **ECC (2-bit) — 정정 불가** | 2bit 이상 에러라서 정정 능력을 초과. 헤더 자체를 신뢰할 수 없음 → packet 전체를 폐기해야 함 |
| **CRC 에러** | Payload 손상 검출 (정정 불가) |
| **Data Type 에러** | Packet Header의 Data ID(DI) 필드가 스펙에 정의되지 않은 값이거나, 지원하지 않는 Data Type인 경우 |
| **Invalid VC 에러** | 지원하는 VC 개수를 초과하는 VC ID가 들어온 경우 |
| **FS / FE 시퀀스 에러** | FS 없이 라인 데이터가 들어오거나, FE 없이 다음 프레임의 FS가 와버리는 등 프레임 경계 프로토콜 위반 |
| **Line Count / Line Number 불일치** | (일부 IP에서 지원) 기대한 라인 수와 실제 수신된 라인 수가 안 맞는 경우 |
| **Timeout 에러** | 특정 시간 내에 기대한 packet이 안 들어와서 watchdog 타임아웃 발생 |

### 3. 인터페이스/버퍼 레벨 (PHY도 CSI-2도 아닌, 그 경계나 후단)

| 에러 | 의미 |
| --- | --- |
| **FIFO Overflow / Underflow** | lane deskew FIFO나 후단 line buffer에서 write가 read보다 너무 빨라(overflow) 또는 느려(underflow) 데이터 유실 |
| **Lane Alignment Timeout** | 특정 시간 내에 모든 레인의 `RxSyncHS`가 다 뜨지 않아서 정렬 자체를 포기하는 경우 |

---

## 각 에러에 대한 대처 방법 스터디

| 에러 수준 | 에러 종류 |
| --- | --- |
| 허용 가능 | ErrSotHS, ECC 1-bit Error |
| 허용 불가 | 나머지 |

### 1. D-PHY PPI 레벨

#### ErrSotHS (반복 발생 시)

**원인 후보**: HS 진입 시 Sync word 근처에서 비트 에러 → 대부분 **타이밍 마진 부족**

**점검 순서**:
1. 발생이 특정 레인에 몰리는지 확인 → 그 레인만 문제면 배선/PCB 이슈
2. 발생이 특정 클럭 속도(고속 모드)에서만 나오는지 확인 → 마진 부족이면 속도 낮춰서 재현 테스트
3. 오실로스코프로 해당 레인의 eye diagram 확인 (가능하면)

**조치**:
- `THS-SETTLE` 값이 너무 짧으면 리시버가 Sync word를 제대로 못 잡는 경우가 흔함 → 오실로스코프로 직접 시퀀스를 찍어서 SETTLE 구간을 확인하는 것이 가장 정확
  - THS-SETTLE: D-PHY 내부 Control Logic에서 HS-0 ~ SoT시퀀스 시작 전까지 HS모듈이 샘플링하는걸 잠시 쉬어가는 시간 (THS-SETTLE ≤ THS-ZERO)을 제어할 수 있는 레지스터
- PCB 배선 문제로 의심되면 **레인별 트레이스 길이 매칭**(±소수 mm 이내) 재검토

#### ErrSotSyncHS (패킷 유실 수준)

**원인 후보**: 위 ErrSotHS보다 심한 SI 문제, 또는 클럭/데이터 레인 간 스큐가 스펙 한계 초과

**조치**:
- (1순위) 타이밍 파라미터 재조정
- 그래도 반복되면 **송신 측(센서) 드라이브 강도(TX swing) 설정** 확인 — 너무 약하면 리시버가 엣지를 못 잡음
- 케이블/커넥터 사용 환경이면 **케이블 길이 단축 또는 임피던스 매칭** 재점검
- 여러 방법으로도 해결 안 되면 **HS 클럭 속도(bps)를 한 단계 낮춰서** 마진 확보 (해상도/프레임레이트 트레이드오프 발생)

#### ErrControl (LP 시퀀스 위반)

**원인 후보**: LP 라인 상태 천이 자체가 스펙 밖 → 대부분 **전원/종단 문제** 또는 **PHY 초기화 시퀀스 버그**

**조치**:
- 전원 시퀀싱(센서 전원 → PHY 전원 → 클럭 인가 순서)이 스펙대로 되는지 재확인
- LP 라인의 풀업/풀다운 종단 저항 값이 스펙(D-PHY: 통상 pull-up 있는 구조) 대로인지 회로 재검토
- 반복되면 초기화 시퀀스(리셋 해제 타이밍, escape mode 진입 타이밍)를 로직 분석기로 캡처해서 스펙과 비교

### 2. CSI-2 Protocol 레벨

#### ECC 2-bit (정정 불가)

**원인 후보**: 헤더 4바이트 자체가 심하게 깨짐 → **HS 데이터 무결성 문제**, 근본 원인은 물리 계층(SI)일 가능성이 매우 높음

**조치**:
- ECC는 헤더에만 붙기 때문에, "헤더에서만 자주 깨진다"면 우연이고 사실상 **HS 데이터 전체 무결성 저하**로 봐야 함
- 1차: ErrSotHS/ErrSotSyncHS와 동시에 증가하는지 확인 → 같이 증가하면 **원인은 동일 (SI 문제)**, D-PHY 레벨 조치(THS-SETTLE, TX swing, 트레이스 매칭)와 동일한 처방
- 특정 VC나 특정 DT에서만 나온다면 → 센서 펌웨어/설정 버그로 헤더 생성 자체가 잘못됐을 가능성 → 센서 벤더에 문의
- ECC 1-bit는 안 나오는데 2-bit만 튄다면 → 노이즈성이 아니라 **버스트 에러(연속 비트 손상)**일 가능성, 이 경우 클럭/데이터 스큐 문제를 우선 의심

#### CRC 에러

**원인 후보**: Payload 구간에서 손상 → 헤더는 멀쩡한데 payload만 깨진다면 **긴 burst 전송 중 마진이 시간이 지나면서 열화**되는 패턴 (예: HS 유지 중 온도 상승, PLL 드리프트)

**점검**:
- 프레임 내에서 에러가 **초반 라인 vs 후반 라인** 중 어디 몰리는지 확인 → 후반에 몰리면 PLL/클럭 드리프트, thermal 이슈 의심
- 특정 라인 길이(WC 값)가 클 때만 발생하는지 확인 → 길수록 누적 지터 영향 커짐

**조치**:
- PLL/클럭 소스 지터 스펙 재확인, 필요시 클럭 소스 교체 또는 필터링(디커플링 커패시터) 보강
- 특정 조건(고온 등)에서만 발생하면 열 설계(방열) 재검토

#### Data Type 에러

**원인 후보**: 대부분 **설정 미스매치**이지 SI 문제가 아님

**조치**:
- 센서가 실제로 보내는 DT 목록과 리시버(IP) 설정에서 지원하도록 등록한 DT 목록을 비교
- 벤더 커스텀 DT(예: embedded data, PDAF 데이터 등)를 리시버가 처리하도록 활성화가 안 돼 있는 경우가 많음 → 리시버 드라이버/레지스터 설정에서 해당 DT 지원 추가
- 이건 하드웨어 문제가 아니라 **소프트웨어/설정 조치**로 해결되는 경우가 대부분

#### Invalid VC 에러

**원인 후보**: 100% **설정 미스매치**

**조치**:
- 센서 측 활성 VC 개수/ID 설정과 리시버 측 지원 VC 설정을 나란히 놓고 재확인 (레지스터 덤프 비교 권장)
- 멀티 카메라 시스템이면 VC 할당표를 다시 검토해서 충돌/초과 없는지 확인

#### FS/FE 시퀀스 에러

**원인 후보**: 대부분 **위의 SoT/ECC 에러로 인해 특정 패킷이 유실**되면서 연쇄적으로 발생 (2차 증상인 경우가 많음)

**조치**:
- 이 에러 단독으로 접근하지 말고, **동시에 ErrSotSyncHS나 ECC 에러가 같이 뜨는지** 먼저 확인
- 같이 뜬다면 근본 원인은 그쪽(SI 문제)이므로 그걸 먼저 해결
- 단독으로만 발생한다면 → 센서 펌웨어가 FS/FE를 잘못된 타이밍에 내보내는 **센서 측 버그**일 가능성 → 벤더 문의 또는 펌웨어 업데이트

#### Timeout 에러

**원인 후보**: 링크 자체가 살아있는지부터 확인 필요

**조치**:
- Clock Lane이 정상적으로 HS로 진입하는지부터 확인 (StopstateClk 등)
- 센서 측 전원/클럭이 정상 공급되는지 확인
- 인터럽트/DMA 등 상위 소프트웨어가 프레임 처리를 지연시켜서 다음 프레임 수신을 막는 **소프트웨어 병목**일 수도 있음 (하드웨어만 보지 말고 상위 드라이버 처리 시간도 프로파일링)

### 3. 인터페이스/버퍼 레벨

#### FIFO Overflow/Underflow

**원인 후보**: 클럭 배속 계산 오류 또는 실제 스큐가 설계 마진을 초과

**조치**:
- `RxByteClk = RxByteClkHS*2` 같은 배속 설정이 실제 레인 수/설정과 일치하는지 레지스터 재확인 (레인 수 변경했는데 배속 설정 안 바꾼 경우 흔함)
- 반복되면 FIFO 깊이를 늘리는 **RTL/IP 파라미터 재설계**가 필요할 수 있음 (이건 소프트웨어로 해결 안 되고 하드웨어 재설계 영역)
- 소프트웨어 워크어라운드로는 힘들고, IP 벤더에게 FIFO depth 파라미터 조정 문의

#### Lane Alignment Timeout

**원인 후보**: 특정 레인만 반복되면 하드웨어(그 레인 배선/커넥터) 문제, 전체 레인이면 클럭 레인 문제

**조치**:
- 어느 레인에서 발생하는지 로그로 특정 → 특정 레인 고정이면 해당 레인 배선/솔더링/커넥터 재점검 (물리적 재작업 필요할 수도)
- 온도나 진동에 따라 간헐적이면 기구적 접촉 불량 의심

### 전체 접근 순서 요약

실무에서는 이렇게 우선순위를 잡는 게 효율적입니다.

1. **여러 에러가 동시에 몰려서 뜨는지 확인** (ErrSotHS ↑ + ECC ↑ + CRC ↑ 같이 증가) → 물리 계층(SI) 문제로 귀결, THS-SETTLE/TX swing/PCB 트레이스부터 점검
2. **단독으로만 특정 에러가 반복** (Invalid VC, Data Type, Timeout) → 대부분 설정 미스매치, 레지스터/드라이버 설정 재확인으로 해결 가능성 높음
3. **특정 레인에만 몰림** → 하드웨어(그 레인만의 배선/드라이버) 문제
4. **온도/시간 경과에 따라 악화** → 열 설계 또는 PLL/클럭 드리프트 문제