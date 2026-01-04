package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/spf13/cobra"
)

var visoCmd = &cobra.Command{
	Use:   "viso",
	Short: "VISO management commands",
	Long: `VISO (Virtual ISO) management for MixOS-GO.

VISO is a revolutionary disk image format that replaces traditional
CDROM/ISO formats. It provides:

  - Optimized for virtio (maximum I/O performance)
  - VRAM mode support (boot from RAM)
  - SDISK boot mechanism
  - qcow2 format with compression

VISO files use the .viso extension and can be booted with:
  qemu-system-x86_64 -drive file=image.viso,format=qcow2,if=virtio`,
}

var visoInfoCmd = &cobra.Command{
	Use:   "info [viso-file]",
	Short: "Show VISO image information",
	Long:  `Display detailed information about a VISO image file.`,
	Args:  cobra.MaximumNArgs(1),
	RunE:  runVisoInfo,
}

var visoListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available VISO images",
	Long:  `List all VISO images in the default locations.`,
	RunE:  runVisoList,
}

var visoBootCmd = &cobra.Command{
	Use:   "boot [viso-file]",
	Short: "Show boot command for VISO",
	Long:  `Display the QEMU command to boot a VISO image.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runVisoBoot,
}

func init() {
	rootCmd.AddCommand(visoCmd)
	visoCmd.AddCommand(visoInfoCmd)
	visoCmd.AddCommand(visoListCmd)
	visoCmd.AddCommand(visoBootCmd)

	visoBootCmd.Flags().Bool("vram", false, "Enable VRAM mode")
	visoBootCmd.Flags().String("memory", "2G", "Memory size")
	visoBootCmd.Flags().Bool("kvm", true, "Enable KVM acceleration")
}

// VISO metadata structure
type VisoMetadata struct {
	Name     string `json:"name"`
	Version  string `json:"version"`
	Format   string `json:"format"`
	Created  string `json:"created"`
	Features struct {
		VramSupport     bool `json:"vram_support"`
		SdiskBoot       bool `json:"sdisk_boot"`
		VirtioOptimized bool `json:"virtio_optimized"`
	} `json:"features"`
	Boot struct {
		Kernel    string `json:"kernel"`
		Initramfs string `json:"initramfs"`
		Cmdline   string `json:"cmdline"`
	} `json:"boot"`
	Rootfs struct {
		Path        string `json:"path"`
		Format      string `json:"format"`
		Compression string `json:"compression"`
	} `json:"rootfs"`
	Requirements struct {
		MinRamMB     int    `json:"min_ram_mb"`
		VramMinRamMB int    `json:"vram_min_ram_mb"`
		Arch         string `json:"arch"`
	} `json:"requirements"`
}

func runVisoInfo(cmd *cobra.Command, args []string) error {
	fmt.Println("")
	fmt.Println("╔══════════════════════════════════════════════════════════════╗")
	fmt.Println("║              VISO - Virtual ISO Format                       ║")
	fmt.Println("║              Revolutionary MixOS-GO Feature                  ║")
	fmt.Println("╚══════════════════════════════════════════════════════════════╝")
	fmt.Println("")

	if len(args) == 0 {
		// Show general VISO information
		fmt.Println("What is VISO?")
		fmt.Println("=============")
		fmt.Println("VISO (Virtual ISO) is a next-generation disk image format")
		fmt.Println("designed for maximum performance and flexibility.")
		fmt.Println("")

		fmt.Println("Features:")
		fmt.Println("=========")
		fmt.Println("  • Replaces traditional CDROM/ISO format")
		fmt.Println("  • Optimized for virtio (QEMU/KVM)")
		fmt.Println("  • VRAM mode support (boot from RAM)")
		fmt.Println("  • SDISK boot mechanism")
		fmt.Println("  • qcow2 format with compression")
		fmt.Println("  • Squashfs rootfs for minimal size")
		fmt.Println("")

		fmt.Println("File Extensions:")
		fmt.Println("================")
		fmt.Println("  .viso      - VISO image (qcow2 format)")
		fmt.Println("  .vram      - VRAM-optimized package")
		fmt.Println("  .VISO      - SDISK boot reference")
		fmt.Println("")

		fmt.Println("Boot Parameters:")
		fmt.Println("================")
		fmt.Println("  SDISK=name.VISO  - Boot from VISO using SDISK")
		fmt.Println("  VRAM=auto        - Enable VRAM mode if RAM sufficient")
		fmt.Println("")

		fmt.Println("Usage:")
		fmt.Println("======")
		fmt.Println("  mix viso info <file.viso>  - Show VISO file details")
		fmt.Println("  mix viso list              - List available VISO images")
		fmt.Println("  mix viso boot <file.viso>  - Show boot command")
		fmt.Println("")

		return nil
	}

	// Show specific VISO file information
	visoPath := args[0]

	// Check if file exists
	info, err := os.Stat(visoPath)
	if err != nil {
		return fmt.Errorf("VISO file not found: %s", visoPath)
	}

	fmt.Printf("VISO File: %s\n", visoPath)
	fmt.Printf("Size:      %.2f MB\n", float64(info.Size())/(1024*1024))
	fmt.Printf("Modified:  %s\n", info.ModTime().Format("2006-01-02 15:04:05"))
	fmt.Println("")

	// Try to read metadata if it's a directory or mounted
	metadataPath := filepath.Join(filepath.Dir(visoPath), "config", "viso.json")
	if data, err := os.ReadFile(metadataPath); err == nil {
		var metadata VisoMetadata
		if err := json.Unmarshal(data, &metadata); err == nil {
			fmt.Println("Metadata:")
			fmt.Println("=========")
			fmt.Printf("  Name:    %s\n", metadata.Name)
			fmt.Printf("  Version: %s\n", metadata.Version)
			fmt.Printf("  Format:  %s\n", metadata.Format)
			fmt.Printf("  Created: %s\n", metadata.Created)
			fmt.Println("")

			fmt.Println("Features:")
			fmt.Printf("  VRAM Support:     %v\n", metadata.Features.VramSupport)
			fmt.Printf("  SDISK Boot:       %v\n", metadata.Features.SdiskBoot)
			fmt.Printf("  Virtio Optimized: %v\n", metadata.Features.VirtioOptimized)
			fmt.Println("")

			fmt.Println("Requirements:")
			fmt.Printf("  Min RAM:      %d MB\n", metadata.Requirements.MinRamMB)
			fmt.Printf("  VRAM Min RAM: %d MB\n", metadata.Requirements.VramMinRamMB)
			fmt.Printf("  Architecture: %s\n", metadata.Requirements.Arch)
		}
	}

	fmt.Println("")
	fmt.Println("Boot Command:")
	fmt.Println("=============")
	fmt.Printf("  qemu-system-x86_64 \\\n")
	fmt.Printf("    -drive file=%s,format=qcow2,if=virtio,cache=writeback,aio=threads \\\n", visoPath)
	fmt.Printf("    -m 2G -cpu host -enable-kvm\n")
	fmt.Println("")

	return nil
}

func runVisoList(cmd *cobra.Command, args []string) error {
	fmt.Println("")
	fmt.Println("Available VISO Images:")
	fmt.Println("======================")
	fmt.Println("")

	// Search locations
	searchPaths := []string{
		".",
		"/var/lib/mixos/images",
		"/opt/mixos/images",
		os.Getenv("HOME") + "/mixos",
	}

	found := false
	for _, searchPath := range searchPaths {
		files, err := filepath.Glob(filepath.Join(searchPath, "*.viso"))
		if err != nil {
			continue
		}

		for _, file := range files {
			info, err := os.Stat(file)
			if err != nil {
				continue
			}

			found = true
			sizeMB := float64(info.Size()) / (1024 * 1024)
			fmt.Printf("  %s (%.2f MB)\n", file, sizeMB)
		}

		// Also check for .viso.tar.gz
		files, _ = filepath.Glob(filepath.Join(searchPath, "*.viso.tar.gz"))
		for _, file := range files {
			info, err := os.Stat(file)
			if err != nil {
				continue
			}

			found = true
			sizeMB := float64(info.Size()) / (1024 * 1024)
			fmt.Printf("  %s (%.2f MB) [archive]\n", file, sizeMB)
		}
	}

	if !found {
		fmt.Println("  No VISO images found.")
		fmt.Println("")
		fmt.Println("  Build a VISO image with: make viso")
	}

	fmt.Println("")
	return nil
}

func runVisoBoot(cmd *cobra.Command, args []string) error {
	visoPath := args[0]
	vramMode, _ := cmd.Flags().GetBool("vram")
	memory, _ := cmd.Flags().GetString("memory")
	kvmEnabled, _ := cmd.Flags().GetBool("kvm")

	// Check if file exists
	if _, err := os.Stat(visoPath); err != nil {
		return fmt.Errorf("VISO file not found: %s", visoPath)
	}

	fmt.Println("")
	fmt.Println("QEMU Boot Command:")
	fmt.Println("==================")
	fmt.Println("")

	var cmdParts []string
	cmdParts = append(cmdParts, "qemu-system-x86_64")
	cmdParts = append(cmdParts, fmt.Sprintf("  -drive file=%s,format=qcow2,if=virtio,cache=writeback,aio=threads", visoPath))
	cmdParts = append(cmdParts, fmt.Sprintf("  -m %s", memory))

	if kvmEnabled {
		cmdParts = append(cmdParts, "  -cpu host")
		cmdParts = append(cmdParts, "  -enable-kvm")
	}

	// Build kernel append line
	appendParts := []string{"console=ttyS0"}
	if vramMode {
		appendParts = append(appendParts, "VRAM=auto")
	}

	// Get VISO name for SDISK
	visoName := filepath.Base(visoPath)
	visoName = strings.TrimSuffix(visoName, ".viso")
	appendParts = append(appendParts, fmt.Sprintf("SDISK=%s.VISO", visoName))

	cmdParts = append(cmdParts, fmt.Sprintf("  -append \"%s\"", strings.Join(appendParts, " ")))
	cmdParts = append(cmdParts, "  -nographic")

	// Print command
	for i, part := range cmdParts {
		if i < len(cmdParts)-1 {
			fmt.Printf("%s \\\n", part)
		} else {
			fmt.Println(part)
		}
	}

	fmt.Println("")

	if vramMode {
		fmt.Println("Note: VRAM mode enabled - system will run from RAM")
		fmt.Println("      Requires minimum 2GB RAM (4GB recommended)")
	}

	fmt.Println("")
	return nil
}
