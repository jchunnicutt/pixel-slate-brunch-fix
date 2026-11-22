# Google Pixel Slate (`nocturne`) Audio & Auto-Rotation Fix for Brunch (`rammus`)

Enable **native internal `MAX98373` stereo speakers**, **internal `avs_dmic` microphones**, **volume slider scaling**, and **automatic screen rotation / tablet mode** on the **Google Pixel Slate (`nocturne`)** running modern **Brunch (`r143` / `r154+`)** with **`rammus`** recovery images (`kernel-chromebook-6.6` or `kernel-chromebook-6.12`).

## Why This Fix Is Needed

1. **AVS Topology Control Handler Mismatch (`0:0:5` at `0xbf4`):** Brunch's `6.6` and `6.12` kernels compile Google's ChromeOS `snd_soc_avs` ABI, which rejects mainline Linux topologies (`control type 257:257:257`) while also dropping the legacy `0:0:5` DSM/WAVES kcontrol handler in `nocturne`'s stock `7,632`-byte `max98373-tplg.bin`.
2. **Missing Kaby Lake AVS DSP Libraries & UCM1 Profiles:** `rammus` omits `nocturne`'s Kaby Lake `intel/avs/skl/` DSP firmware libraries (`dsp_lib_dsm_core_spt_release.bin`, `dsp_lib_waves5_9_spt_release.bin`) and UCM1 `avs_max98373` / `avs_dmic` configs.
3. **Tablet Accelerometer & Pogo-Pin Dock Orientation:** Without `ACCEL_LOCATION="lid"` on `iio:device0` and unbinding `cbas_ec` (`GOOG000B:00`), ChromeOS locks in landscape laptop mode.

## Quick Start

### Option A: Run From a Linux Dual-Boot / Live USB
```bash
chmod +x install-nocturne-brunch-fix.sh
sudo ./install-nocturne-brunch-fix.sh \
  --recovery /path/to/chromeos_16667.62.0_nocturne_recovery_stable-channel_NocturneMPKeys-v8.bin \
  --target /path/to/chromeos.img \
  --kernel 6.12
```

### Option B: Run Directly Inside ChromeOS (`VT-2`)
1. Press **`Ctrl + Alt + F2`**, log in as `chronos`, and run:
   ```bash
   sudo bash install-nocturne-brunch-fix.sh \
     --recovery /home/chronos/user/MyFiles/Downloads/chromeos_16667.62.0_nocturne_recovery_stable-channel_NocturneMPKeys-v8.bin \
     --target /dev/sdz \
     --kernel 6.12
   ```
2. Perform a **full cold shutdown** (`sudo poweroff`), then power back on.

## Updating Brunch Later
* **ChromeOS Updates (`chromeos-update`):** Survive automatically.
* **Brunch Framework Updates (`brunch-update`):** Reapply your saved archive before rebooting:
  ```bash
  sudo bash install-nocturne-brunch-fix.sh --restore /path/to/nocturne_brunch_backup.tar.gz --target /dev/sdz
  ```

## Bonus: Stop Power Button From Shutting Down After Sleep on Linux Dual-Boot
```bash
sudo mkdir -p /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/99-pixel-slate-power.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
EOF
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'
sudo systemctl reload systemd-logind
```
