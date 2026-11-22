#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"

RECOVERY_BIN=""
TARGET=""
RESTORE_TAR=""
KERNEL_VER="6.12"

usage() {
  cat << 'EOF'
Usage: sudo ./install-nocturne-brunch-fix.sh [OPTIONS]

Options:
  -r, --recovery <path>   Path to unzipped stock nocturne recovery .bin image
  -t, --target <path>     Target Brunch chromeos.img file or block device (e.g. /dev/sdz)
  -k, --kernel <6.6|6.12> Brunch kernel version to configure in settings.cfg (default: 6.12)
      --restore <tar.gz>  Restore from an existing nocturne_brunch_backup.tar.gz (skips --recovery)
  -h, --help              Show this help message
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--recovery) RECOVERY_BIN="$2"; shift 2 ;;
    -t|--target)   TARGET="$2"; shift 2 ;;
    -k|--kernel)   KERNEL_VER="$2"; shift 2 ;;
    --restore)     RESTORE_TAR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             echo "Unknown option: $1"; usage ;;
  esac
done

[[ $EUID -ne 0 ]] && { echo "Error: Please run as root (sudo)."; exit 1; }
[[ -z "$TARGET" ]] && { echo "Error: --target is required."; usage; }
[[ -z "$RESTORE_TAR" && -z "$RECOVERY_BIN" ]] && { echo "Error: --recovery or --restore required."; usage; }
[[ "$KERNEL_VER" != "6.6" && "$KERNEL_VER" != "6.12" ]] && { echo "Error: --kernel must be 6.6 or 6.12."; exit 1; }

WORK_DIR=$(mktemp -d /tmp/nocturne_brunch_work.XXXXXX)
REC_LOOP=""
TGT_LOOP=""

cleanup() {
  set +e
  umount "$WORK_DIR/rec_p3" "$WORK_DIR/tgt_p7" "$WORK_DIR/tgt_p12" 2>/dev/null
  [[ -n "$REC_LOOP" ]] && losetup -d "$REC_LOOP" 2>/dev/null
  [[ -n "$TGT_LOOP" ]] && losetup -d "$TGT_LOOP" 2>/dev/null
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/rec_p3" "$WORK_DIR/tgt_p7" "$WORK_DIR/tgt_p12" "$WORK_DIR/stage"

if [[ -f "$TARGET" ]]; then
  TGT_LOOP=$(losetup -fP --show "$TARGET")
  P7_DEV="${TGT_LOOP}p7"
  P12_DEV="${TGT_LOOP}p12"
  BACKUP_OUT="$(dirname "$(realpath "$TARGET")")/nocturne_brunch_backup.tar.gz"
elif [[ -b "$TARGET" ]]; then
  if [[ "$TARGET" =~ [0-9]$ ]]; then
    P7_DEV="${TARGET}p7"; P12_DEV="${TARGET}p12"
  else
    P7_DEV="${TARGET}7"; P12_DEV="${TARGET}12"
  fi
  BACKUP_OUT="/tmp/nocturne_brunch_backup.tar.gz"
else
  echo "Error: Target '$TARGET' does not exist."; exit 1
fi

mount "$P7_DEV" "$WORK_DIR/tgt_p7"
mount "$P12_DEV" "$WORK_DIR/tgt_p12"
if [[ -n "$RESTORE_TAR" ]]; then
  echo "[1/3] Restoring from backup archive: $RESTORE_TAR"
  tar -xzf "$RESTORE_TAR" -C "$WORK_DIR/stage"
else
  echo "[1/4] Mounting nocturne recovery image: $RECOVERY_BIN"
  REC_LOOP=$(losetup -fP --show "$RECOVERY_BIN")
  mount -o ro "${REC_LOOP}p3" "$WORK_DIR/rec_p3"

  ORIG_TPLG="$WORK_DIR/rec_p3/lib/firmware/intel/avs/max98373-tplg.bin"
  [[ ! -f "$ORIG_TPLG" ]] && { echo "Error: max98373-tplg.bin not found in recovery image."; exit 1; }

  echo "[2/4] Binary-patching max98373-tplg.bin..."
  mkdir -p "$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/skl"
  mkdir -p "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm"

  dd if="$ORIG_TPLG" bs=1 count=2764 of="$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/max98373-tplg.bin" 2>/dev/null
  dd if="$ORIG_TPLG" bs=1 skip=3320 >> "$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/max98373-tplg.bin" 2>/dev/null

  cp -af "$WORK_DIR/rec_p3/lib/firmware/intel/avs/dmic-tplg.bin" "$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/"
  cp -af "$WORK_DIR/rec_p3/lib/firmware/intel/avs/hda-8086280b-tplg.bin" "$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/" 2>/dev/null || true
  cp -af "$WORK_DIR/rec_p3/lib/firmware/intel/avs/skl/"* "$WORK_DIR/stage/nocturne_audio/lib/firmware/intel/avs/skl/"

  echo "[3/4] Generating UCM1 profiles and Brunch boot patch script..."
  cat << 'EOF' > "$WORK_DIR/HiFi_max98373.conf"
SectionVerb {
	Value {
		FullySpecifiedUCM "1"
		DefaultVolumeCurve "simple_step"
	}
	EnableSequence [
		cdev "hw:avsmax98373"
		cset "name='Left DAI Sel Mux' Left"
		cset "name='Right DAI Sel Mux' Right"
		cset "name='Left Output Voltage' 4"
		cset "name='Right Output Voltage' 4"
		cset "name='Left Speaker Volume' 7"
		cset "name='Right Speaker Volume' 7"
		cset "name='Left Digital Volume' 115"
		cset "name='Right Digital Volume' 115"
		cset "name='Left Digital Vol Sel Switch' 1"
		cset "name='Right Digital Vol Sel Switch' 1"
		cset "name='Left Spk Switch' off"
		cset "name='Right Spk Switch' off"
	]
	DisableSequence [
	]
}
SectionDevice."Speaker".0 {
	Value {
		PlaybackPCM "hw:avsmax98373,1"
		DisableSoftwareVolume "0"
	}
	EnableSequence [
		cdev "hw:avsmax98373"
		cset "name='Left Output Voltage' 5"
		cset "name='Right Output Voltage' 5"
		cset "name='Left DHT Switch' on"
		cset "name='Right DHT Switch' on"
		cset "name='Left BDE Switch' on"
		cset "name='Right BDE Switch' on"
		cset "name='Left VI Sense Switch' on"
		cset "name='Right VI Sense Switch' on"
		cset "name='Left Spk Switch' on"
		cset "name='Right Spk Switch' on"
	]
	DisableSequence [
		cdev "hw:avsmax98373"
		cset "name='Left Spk Switch' off"
		cset "name='Right Spk Switch' off"
		cset "name='Left VI Sense Switch' off"
		cset "name='Right VI Sense Switch' off"
		cset "name='Left DHT Switch' off"
		cset "name='Right DHT Switch' off"
		cset "name='Left BDE Switch' off"
		cset "name='Right BDE Switch' off"
	]
}
EOF
  for DIR in avs_max98373 avsmax98373; do
    mkdir -p "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}"
    cp -f "$WORK_DIR/HiFi_max98373.conf" "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}/HiFi.conf"
    printf 'Comment "Nocturne internal speakers"\nSectionUseCase."HiFi" {\n\tFile "HiFi.conf"\n\tComment "Default"\n}\n' > "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}/${DIR}.conf"
  done

  for DIR in avs_dmic avsdmic; do
    mkdir -p "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}"
    printf 'SectionVerb {\n\tValue {\n\t\tFullySpecifiedUCM "1"\n\t}\n\tEnableSequence [\n\t]\n\tDisableSequence [\n\t]\n}\nSectionDevice."Internal Mic".0 {\n\tValue {\n\t\tCapturePCM "hw:avsdmic,2"\n\t}\n}\n' > "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}/HiFi.conf"
    printf 'Comment "Nocturne internal mic"\nSectionUseCase."HiFi" {\n\tFile "HiFi.conf"\n\tComment "Default"\n}\n' > "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/${DIR}/${DIR}.conf"
  done

  mkdir -p "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/hdaudioB0D2"
  printf 'SectionVerb {\n\tValue {\n\t\tFullySpecifiedUCM "1"\n\t}\n\tEnableSequence [\n\t]\n\tDisableSequence [\n\t]\n}\nSectionDevice."HDMI1".0 {\n\tValue {\n\t\tPlaybackPCM "hw:hdaudioB0D2,1"\n\t\tJackDev "hdaudioB0D2 HDMI/DP,pcm=1 Jack"\n\t}\n}\nSectionDevice."HDMI2".0 {\n\tValue {\n\t\tPlaybackPCM "hw:hdaudioB0D2,2"\n\t\tJackDev "hdaudioB0D2 HDMI/DP,pcm=2 Jack"\n\t}\n}\nSectionDevice."HDMI3".0 {\n\tValue {\n\t\tPlaybackPCM "hw:hdaudioB0D2,3"\n\t\tJackDev "hdaudioB0D2 HDMI/DP,pcm=3 Jack"\n\t}\n}\n' > "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/hdaudioB0D2/HiFi.conf"
  printf 'Comment "Nocturne HDMI"\nSectionUseCase."HiFi" {\n\tFile "HiFi.conf"\n\tComment "Default"\n}\n' > "$WORK_DIR/stage/nocturne_audio/usr/share/alsa/ucm/hdaudioB0D2/hdaudioB0D2.conf"

  cat << 'EOF' > "$WORK_DIR/stage/99-nocturne_audio.sh"
#!/bin/bash
echo "GOOG000B:00" > /sys/bus/platform/drivers/cbas_ec/unbind 2>/dev/null || true
echo 'SUBSYSTEM=="iio", KERNEL=="iio:device0", ENV{ACCEL_LOCATION}="lid"' > /etc/udev/rules.d/99-nocturne-accel.rules
echo "--force-tablet-mode=touch_view" >> /etc/chrome_dev.conf

rm -f /lib/firmware/intel/avs/*-tplg.bin*
cp -rf /rootc/nocturne_audio/lib/firmware/intel/avs/* /lib/firmware/intel/avs/
mkdir -p /usr/local/nocturne_ucm
cp -rf /rootc/nocturne_audio/usr/share/alsa/ucm/* /usr/local/nocturne_ucm/

if ! grep -q "nocturne_ucm" /usr/share/cros/init/cras.sh; then
  sed -i '2i rm -rf /usr/share/alsa/ucm*/hdaudioB0D2.* /usr/share/alsa/ucm*/avs_dmic.leona /usr/share/alsa/ucm*/avs_dmic.shyvana* 2>/dev/null || true; mkdir -p /usr/share/alsa/ucm && cp -rf /usr/local/nocturne_ucm/* /usr/share/alsa/ucm/' /usr/share/cros/init/cras.sh
fi
exit 0
EOF
  chmod +x "$WORK_DIR/stage/99-nocturne_audio.sh"
fi

echo "[4/4] Installing patch onto Brunch ROOT-C and updating settings.cfg..."
rm -rf "$WORK_DIR/tgt_p7/nocturne_audio"
mkdir -p "$WORK_DIR/tgt_p7/patches"
cp -af "$WORK_DIR/stage/nocturne_audio" "$WORK_DIR/tgt_p7/"
cp -af "$WORK_DIR/stage/99-nocturne_audio.sh" "$WORK_DIR/tgt_p7/patches/"
chmod +x "$WORK_DIR/tgt_p7/patches/99-nocturne_audio.sh"

SETTINGS_CFG="$WORK_DIR/tgt_p12/efi/boot/settings.cfg"
if [[ -f "$WORK_DIR/stage/settings.cfg" && -n "$RESTORE_TAR" ]]; then
  cp -af "$WORK_DIR/stage/settings.cfg" "$SETTINGS_CFG"
else
  sed -i -E "s|^kernel=\"/kernel-chromebook-[0-9.]+\"|kernel=\"/kernel-chromebook-${KERNEL_VER}\"|" "$SETTINGS_CFG"
  for OPT in pwa chromebook_audio patches force_tablet_mode; do
    if ! grep -E "^options=" "$SETTINGS_CFG" | grep -q "$OPT"; then
      sed -i -E "s|^options=\"([^\"]*)\"|options=\"\1,${OPT}\"|" "$SETTINGS_CFG"
    fi
  done
  sed -i 's|options=",|options="|g' "$SETTINGS_CFG"
  if ! grep -E "^cmdline_params=" "$SETTINGS_CFG" | grep -q "snd-intel-dspcfg.dsp_driver=4"; then
    sed -i -E 's|^cmdline_params="([^"]*)"|cmdline_params="\1 snd-intel-dspcfg.dsp_driver=4 "|' "$SETTINGS_CFG"
  fi
fi

cp -af "$SETTINGS_CFG" "$WORK_DIR/stage/settings.cfg"
tar -czf "$BACKUP_OUT" -C "$WORK_DIR/stage" .

echo "Success! Installed Pixel Slate audio & auto-rotation fix."
grep -E "^(kernel|options|cmdline_params)=" "$SETTINGS_CFG"
echo "Backup archive saved to: $BACKUP_OUT"
echo "IMPORTANT: Perform a full cold shutdown (sudo poweroff) before booting ChromeOS."
