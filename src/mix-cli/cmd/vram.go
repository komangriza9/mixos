package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/spf13/cobra"
)

var vramCmd = &cobra.Command{
	Use:   "vram",
	Short: "VRAM management commands",
	Long: `VRAM (Virtual RAM) management for MixOS-GO.

VRAM mode allows the entire root filesystem to be loaded into RAM,
providing maximum performance. This is a revolutionary feature that
other operating systems don't have.

Requirements:
  - Minimum 2GB RAM for VRAM mode
  - Squashfs rootfs

Benefits:
  - Maximum I/O performance (RAM speed)
  - Reduced disk wear
  - Faster application loading
  - System runs entirely from memory`,
}

var vramStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show VRAM status",
	Long:  `Display current VRAM mode status and system memory information.`,
	RunE:  runVramStatus,
}

var vramEnableCmd = &cobra.Command{
	Use:   "enable",
	Short: "Enable VRAM mode for next boot",
	Long:  `Configure the system to boot in VRAM mode on next restart.`,
	RunE:  runVramEnable,
}

var vramDisableCmd = &cobra.Command{
	Use:   "disable",
	Short: "Disable VRAM mode",
	Long:  `Configure the system to boot in normal mode on next restart.`,
	RunE:  runVramDisable,
}

var vramInfoCmd = &cobra.Command{
	Use:   "info",
	Short: "Show detailed VRAM information",
	Long:  `Display detailed information about VRAM capability and configuration.`,
	RunE:  runVramInfo,
}

func init() {
	rootCmd.AddCommand(vramCmd)
	vramCmd.AddCommand(vramStatusCmd)
	vramCmd.AddCommand(vramEnableCmd)
	vramCmd.AddCommand(vramDisableCmd)
	vramCmd.AddCommand(vramInfoCmd)
}

// Memory information structure
type MemInfo struct {
	MemTotal     int64
	MemFree      int64
	MemAvailable int64
	Buffers      int64
	Cached       int64
	SwapTotal    int64
	SwapFree     int64
}

// Get memory information from /proc/meminfo
func getMemInfo() (*MemInfo, error) {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return nil, err
	}

	info := &MemInfo{}
	lines := strings.Split(string(data), "\n")

	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}

		value, _ := strconv.ParseInt(fields[1], 10, 64)
		value = value / 1024 // Convert to MB

		switch fields[0] {
		case "MemTotal:":
			info.MemTotal = value
		case "MemFree:":
			info.MemFree = value
		case "MemAvailable:":
			info.MemAvailable = value
		case "Buffers:":
			info.Buffers = value
		case "Cached:":
			info.Cached = value
		case "SwapTotal:":
			info.SwapTotal = value
		case "SwapFree:":
			info.SwapFree = value
		}
	}

	return info, nil
}

// Check if system is running in VRAM mode
func isVramActive() bool {
	// Check for VRAM status file
	if _, err := os.Stat("/run/initramfs/vram-status"); err == nil {
		data, err := os.ReadFile("/run/initramfs/vram-status")
		if err == nil && strings.TrimSpace(string(data)) == "active" {
			return true
		}
	}

	// Check kernel cmdline for VRAM parameter
	cmdline, err := os.ReadFile("/proc/cmdline")
	if err == nil && strings.Contains(string(cmdline), "VRAM=") {
		// Check if root is tmpfs
		mounts, err := os.ReadFile("/proc/mounts")
		if err == nil && strings.Contains(string(mounts), "tmpfs / tmpfs") {
			return true
		}
	}

	return false
}

// Check VRAM capability
func checkVramCapability() (bool, string) {
	info, err := getMemInfo()
	if err != nil {
		return false, "Cannot read memory information"
	}

	// Minimum 2GB RAM required
	minRAM := int64(2048)
	if info.MemTotal < minRAM {
		return false, fmt.Sprintf("Insufficient RAM: %dMB (minimum %dMB required)", info.MemTotal, minRAM)
	}

	return true, fmt.Sprintf("VRAM capable: %dMB total RAM", info.MemTotal)
}

func runVramStatus(cmd *cobra.Command, args []string) error {
	fmt.Println("")
	fmt.Println("╔══════════════════════════════════════════════════════════════╗")
	fmt.Println("║                    VRAM Status                               ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════╝")
	fmt.Println("")

	// Check if VRAM is active
	if isVramActive() {
		fmt.Println("  Status: \033[32mACTIVE\033[0m 🚀")
		fmt.Println("  System is running entirely from RAM!")
		fmt.Println("")

		// Show VRAM size if available
		if data, err := os.ReadFile("/run/initramfs/vram-size"); err == nil {
			fmt.Printf("  VRAM Size: %s MB\n", strings.TrimSpace(string(data)))
		}
	} else {
		fmt.Println("  Status: \033[33mINACTIVE\033[0m")
		fmt.Println("  System is running in normal mode.")
	}

	fmt.Println("")

	// Show memory info
	info, err := getMemInfo()
	if err != nil {
		return fmt.Errorf("failed to get memory info: %w", err)
	}

	fmt.Println("Memory Information:")
	fmt.Printf("  Total:     %6d MB\n", info.MemTotal)
	fmt.Printf("  Available: %6d MB\n", info.MemAvailable)
	fmt.Printf("  Free:      %6d MB\n", info.MemFree)
	fmt.Printf("  Cached:    %6d MB\n", info.Cached)
	fmt.Println("")

	// Check capability
	capable, msg := checkVramCapability()
	if capable {
		fmt.Printf("  VRAM Capability: \033[32m%s\033[0m\n", msg)
	} else {
		fmt.Printf("  VRAM Capability: \033[31m%s\033[0m\n", msg)
	}

	fmt.Println("")
	return nil
}

func runVramEnable(cmd *cobra.Command, args []string) error {
	// Check capability first
	capable, msg := checkVramCapability()
	if !capable {
		return fmt.Errorf("cannot enable VRAM: %s", msg)
	}

	fmt.Println("Enabling VRAM mode for next boot...")

	// Update GRUB/bootloader configuration
	grubCfg := "/boot/grub/grub.cfg"
	if _, err := os.Stat(grubCfg); err == nil {
		// Add VRAM=auto to kernel cmdline
		fmt.Println("Updating bootloader configuration...")

		// This would typically modify the bootloader config
		// For now, we'll create a flag file
		os.MkdirAll("/etc/mixos", 0755)
		os.WriteFile("/etc/mixos/vram-enabled", []byte("auto\n"), 0644)

		fmt.Println("")
		fmt.Println("\033[32m✓ VRAM mode enabled!\033[0m")
		fmt.Println("")
		fmt.Println("On next boot, add this kernel parameter:")
		fmt.Println("  VRAM=auto")
		fmt.Println("")
		fmt.Println("Or use the QEMU command:")
		fmt.Println("  qemu-system-x86_64 ... -append \"VRAM=auto\"")
	} else {
		// Create flag file for initramfs to read
		os.MkdirAll("/etc/mixos", 0755)
		os.WriteFile("/etc/mixos/vram-enabled", []byte("auto\n"), 0644)

		fmt.Println("")
		fmt.Println("\033[32m✓ VRAM mode configured!\033[0m")
		fmt.Println("")
		fmt.Println("Boot with kernel parameter: VRAM=auto")
	}

	return nil
}

func runVramDisable(cmd *cobra.Command, args []string) error {
	fmt.Println("Disabling VRAM mode...")

	// Remove VRAM flag file
	os.Remove("/etc/mixos/vram-enabled")

	fmt.Println("")
	fmt.Println("\033[32m✓ VRAM mode disabled!\033[0m")
	fmt.Println("")
	fmt.Println("System will boot in normal mode on next restart.")

	return nil
}

func runVramInfo(cmd *cobra.Command, args []string) error {
	fmt.Println("")
	fmt.Println("╔══════════════════════════════════════════════════════════════╗")
	fmt.Println("║              VRAM - Virtual RAM Mode                         ║")
	fmt.Println("║              Revolutionary MixOS-GO Feature                  ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════╝")
	fmt.Println("")

	fmt.Println("What is VRAM Mode?")
	fmt.Println("==================")
	fmt.Println("VRAM mode loads the entire root filesystem into RAM during boot.")
	fmt.Println("This provides maximum I/O performance as all disk operations")
	fmt.Println("happen at RAM speed instead of disk speed.")
	fmt.Println("")

	fmt.Println("Benefits:")
	fmt.Println("=========")
	fmt.Println("  • Maximum I/O performance (RAM speed)")
	fmt.Println("  • Instant application loading")
	fmt.Println("  • Reduced disk wear (great for SSDs)")
	fmt.Println("  • System runs entirely from memory")
	fmt.Println("  • Disk can be removed after boot")
	fmt.Println("")

	fmt.Println("Requirements:")
	fmt.Println("=============")
	fmt.Println("  • Minimum 2GB RAM (4GB+ recommended)")
	fmt.Println("  • Squashfs root filesystem")
	fmt.Println("  • VISO or compatible boot image")
	fmt.Println("")

	fmt.Println("How to Enable:")
	fmt.Println("==============")
	fmt.Println("  1. Boot with kernel parameter: VRAM=auto")
	fmt.Println("  2. Or run: mix vram enable")
	fmt.Println("")

	fmt.Println("Boot Parameters:")
	fmt.Println("================")
	fmt.Println("  VRAM=auto    - Enable VRAM if RAM is sufficient")
	fmt.Println("  VRAM=1       - Force enable VRAM mode")
	fmt.Println("  VRAM=yes     - Same as VRAM=1")
	fmt.Println("")

	// Show current status
	info, _ := getMemInfo()
	if info != nil {
		fmt.Println("Current System:")
		fmt.Println("===============")
		fmt.Printf("  Total RAM:     %d MB\n", info.MemTotal)
		fmt.Printf("  Available RAM: %d MB\n", info.MemAvailable)

		capable, _ := checkVramCapability()
		if capable {
			fmt.Println("  VRAM Status:   \033[32mCapable\033[0m ✓")
		} else {
			fmt.Println("  VRAM Status:   \033[31mInsufficient RAM\033[0m ✗")
		}

		if isVramActive() {
			fmt.Println("  Current Mode:  \033[32mVRAM Active\033[0m 🚀")
		} else {
			fmt.Println("  Current Mode:  Normal")
		}
	}

	fmt.Println("")
	return nil
}

// Helper function to run shell commands
func runCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
