NVPermissive Compat 一键兼容包
================================

本包是 NVPermissiveEFI 解锁工具的"兼容性加强版"，针对多台机器实测
（modt 主板 / B660M / X99 等）暴露出的问题做了两项二进制级修复，
并附带现场诊断工具。部署方式采用 {bootmgr} 劫持 + 兜底双保险，
在任何主板上都能一键安装、失败也能正常进系统。

一、与之前版本的区别
--------------------
NVPermissiveCompat.efi = NVPermissiveDirect.efi + 2 字节补丁，共与
原版工具（v0.2.2）相差 4 字节：

  补丁1（Direct 继承，偏移 0x21FA）：无参数默认模式 检查→解锁(windows)，
        即使引导项没传参数也会执行解锁，不再空跑。
  补丁2（新增，偏移 0x37F3/0x37F5）：链式启动判断"恰好 1 个 Windows
        分区"→"至少 1 个即链启"。
        原版：找不到或找到多个 bootmgfw.efi 就拒载（refused）。
        现在：双系统 / 多 ESP / 插着 Windows 安装盘都能正常链启。

二、文件清单
------------
  Install-Compat.bat        一键安装（管理员运行）
  Rollback-Compat.bat       一键回滚（-Full 连工具文件一起删）
  Install-Compat.ps1        安装脚本本体（bat 调用）
  Rollback-Compat.ps1       回滚脚本本体
  NVPermissiveCompat.efi    补丁版解锁工具
  BOOTX64.EFI               UEFI Shell（U盘直启用）
  startup.nsh               U盘直启脚本（含 pci 显卡诊断）
  hashes.txt                SHA256 校验值

三、安装（Windows 一键）
------------------------
  1. 把整个文件夹拷贝到目标机器
  2. 进 BIOS 关闭 Secure Boot（工具未签名）
  3. 右键 Install-Compat.bat → 以管理员身份运行
  4. 重启 → 开机出现工具画面一次 → 自动进系统
  5. GPU-Z 验证 PCIe x16 2.0 = 成功

四、U盘直启（免安装、其他机器测试用）
------------------------------------
  把本文件夹内容放到 FAT32 U 盘根目录，开机选 U 盘 UEFI 启动即可。
  startup.nsh 会依次：[0/3] 列出 PCI 设备（诊断用）→ [1/3] 跑
  Compat → [2/3] 跑旧版工具（兜底）→ [3/3] 直接进 Windows。
  开机插着本 U 盘不影响链启（补丁2 已消除多分区拒载问题）。

五、支持芯片
------------
  仅支持：GA102（90HX/3080/3090）、TU102、TU104、TU106。
  P104/P106 等 GP10x 芯片无代码路径，不支持（屏幕会提示
  "no supported NVPermissive device found"）。

六、失败现象对照表（实测三台机器总结）
--------------------------------------
  现象A：几秒钟直接进系统、没解锁、无报错
    根因：开机时工具没扫到受支持的卡（PCI 枚举问题）。
    对策：①U盘直启看 [0/3] pci 列表里有没有 10DE 开头的行——
           没有 = 主板没枚举到卡：检查 BIOS"挖矿模式"/CSM 设置、
           换槽、换 riser；②有 = 卡在脏状态：完全断电（拔电源线
           等 10 秒）后重试；③检查显卡供电线是否插满。

  现象B：几秒钟报错 FAILED(-1)，SM_SPEED_SELECT_1 写回不匹配
    根因：显卡 SEC2/GSP 固件引导失败（工具内嵌固件与该卡/该板
          组合初始化失败）。
    对策：①完全断电重试（工具自己要求）；②BIOS 关 ASPM；
          ③换 PCIe 插槽 / 换 riser；④主板 BIOS 更新。

  现象C：跑两分钟报错 FAILED(-3)，GSP post-cleanup CPUCTL=0x10
    根因：GSP falcon 引导失败（SEC2 正常、GSP 起不来）。
    对策：同现象B。两分钟=工具把重试预算跑满了，说明卡在板子上
          始终起不来，优先换槽/完全断电。

  现象D：开机正常但 GPU-Z 仍是 PCIe 1.1
    根因：解锁未生效且工具没报错（极少见）。
    对策：重跑 Install-Compat.bat；确认 {bootmgr} 第一、兜底第二；
          用 startup.nsh 的 pci 列表确认卡被枚举。

七、回滚
--------
  右键 Rollback-Compat.bat 管理员运行：恢复 {bootmgr} → 删兜底项。
  加 -Full：连 ESP 上的工具文件一起删除，回到纯原样。

八、哈希校验
------------
  见 hashes.txt。安装脚本会自动校验 Compat 的 SHA256，
  与记录不符会直接中止，防止坏文件上机。
