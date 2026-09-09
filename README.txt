====================================================================
 NVPermissive 直启版一键安装包（90HX PCIe 解锁，免 UEFI Shell 直启）
====================================================================

本包在原有 U 盘工具方案的基础上，新增一个"直启版"工具：
  固件 -> NVPermissiveDirect.efi（补丁版，无参数默认 = windows 模式）-> 解锁 -> 启动 Windows

与旧方案的区别：不再经过 UEFI Shell 中转，开机更快（省约 1~5 秒）。

【状态】已于 2026-09-09 在验证机实测通过：直启进系统正常，GPU-Z 确认
  链路为 PCIe x16 2.0。新机器可直接运行 install.bat 安装。

【文件清单】
  NVPermissiveDirect.efi   补丁版工具（仅 2 字节补丁：默认模式 inspect -> windows）
  NVPermissiveEFI.efi      原版工具（回退链用，未做任何修改）
  BOOTX64.EFI              UEFI Shell（回退链用）
  startup.nsh              Shell 脚本（回退链用）
  install.bat              一键安装（直启项置顶，推荐）
  install_test.bat         测试模式安装（直启项追加到启动顺序末尾，先手动验证）
  Rollback-DirectBoot.bat  回滚（默认只删直启项；加 -Full 参数全删）

【一键安装步骤】（目标机器上）
  1. 把整个文件夹拷到目标机器（任意位置）
  2. 确认 BIOS 里 Secure Boot 已关闭（旧方案已关闭则跳过）
  3. 右键 install.bat -> 以管理员身份运行
  4. 重启。引导顺序为：
       ① 直启解锁（快）
       ② Shell 解锁（回退，慢一点但功能相同）
       ③ Windows Boot Manager
     若 ① 启动失败，固件自动落到 ②，解锁照常执行，系统照常进入。
  5. 开机后用 GPU-Z 确认 90HX 链路为 PCIe x16 2.0

【保守用法（可选）】
  本包已在验证机实测通过，一般可直接 install.bat。若想在新机器上先试后装：
  先运行 install_test.bat（直启项排在最后、不改变默认），重启时从固件
  启动菜单（F8/F11/F12，看主板）手动选 "NVPermissive Direct Boot" 试一次，
  确认进系统 + GPU-Z 显示 2.0 后，再运行 install.bat 将其置顶。

【回滚】
  右键 Rollback-DirectBoot.bat 以管理员运行：
    - 无参数：只删除直启项和补丁文件，回退到旧的 Shell 解锁链（照常解锁）
    - -Full  ：全部删除，回到纯 Windows 引导（卡会回到 1.1 状态）
  紧急救援：插原版 U 盘工具开机，U 盘的 startup.nsh 仍会解锁并链式启动
  Windows，进系统后运行回滚脚本即可。

【注意事项】
  * Windows 大版本更新可能重置引导顺序（解锁失效）-> 重跑 install.bat 即可
  * Secure Boot 必须保持关闭，否则未签名的 EFI 工具会被拒绝执行
  * 建议关闭/暂停 BitLocker 驱动器加密（修改引导链可能触发恢复模式）
  * 解锁状态为内存级：每次开机由工具重新执行，断电即失效，属正常
  * 若直启项开机卡死（极小概率，本包已实测通过），强制断电后
    从固件启动菜单选 Shell 解锁项或 U 盘启动，然后运行回滚脚本
  * 若机器装的是纯 Shell 方案（方案 B 安装包）并用其回滚，请用方案 B
    包内的 Rollback.bat；本包的 Rollback-DirectBoot.bat 只管理直启版组件

【哈希校验值】（安装脚本会自动校验，此处备查）
  NVPermissiveDirect.efi  SHA256 93F29A5764B4A50AFB69B5DB7D1E574E7009554C48E6619BB83C5CA33191F59C
  NVPermissiveEFI.efi     SHA256 1D076198F8D81A173514EA31785E81949E6ED44B3B810F25B8311557DC11F75B
  BOOTX64.EFI             SHA256 DA5F4AA2008E6E26C3553B3DEE4CF835CEAC88820658693704CEA35F62733CE3
  startup.nsh             SHA256 08AA7D011B8EC0971294D234364AD969764F59B5F36D74061C1BA1B12772008D
====================================================================
