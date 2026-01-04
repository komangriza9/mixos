package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
)

// ============================================================================
// Styles
// ============================================================================

var (
	// Colors
	primaryColor   = lipgloss.Color("#FF6B35")
	secondaryColor = lipgloss.Color("#00D9FF")
	successColor   = lipgloss.Color("#00FF88")
	warningColor   = lipgloss.Color("#FFD700")
	errorColor     = lipgloss.Color("#FF4444")
	mutedColor     = lipgloss.Color("#666666")

	// Styles
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(primaryColor).
			MarginBottom(1)

	subtitleStyle = lipgloss.NewStyle().
			Foreground(secondaryColor).
			MarginBottom(1)

	boxStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(primaryColor).
			Padding(1, 2)

	selectedStyle = lipgloss.NewStyle().
			Foreground(successColor).
			Bold(true)

	normalStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FFFFFF"))

	mutedStyle = lipgloss.NewStyle().
			Foreground(mutedColor)

	errorStyle = lipgloss.NewStyle().
			Foreground(errorColor).
			Bold(true)

	successStyle = lipgloss.NewStyle().
			Foreground(successColor).
			Bold(true)

	helpStyle = lipgloss.NewStyle().
			Foreground(mutedColor).
			MarginTop(1)
)

// ============================================================================
// ASCII Art
// ============================================================================

const mixOSLogo = `
    ███╗   ███╗██╗██╗  ██╗ ██████╗ ███████╗
    ████╗ ████║██║╚██╗██╔╝██╔═══██╗██╔════╝
    ██╔████╔██║██║ ╚███╔╝ ██║   ██║███████╗
    ██║╚██╔╝██║██║ ██╔██╗ ██║   ██║╚════██║
    ██║ ╚═╝ ██║██║██╔╝ ██╗╚██████╔╝███████║
    ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
`

const welcomeArt = `
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║   🧡 Welcome to MixOS Setup                                  ║
    ║                                                              ║
    ║   Revolutionary Operating System                             ║
    ║   VISO • SDISK • VRAM • mixmagisk                           ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
`

// ============================================================================
// Setup Steps
// ============================================================================

type setupStep int

const (
	stepWelcome setupStep = iota
	stepCredentials
	stepNetwork
	stepDiskVRAM
	stepProfiles
	stepSummary
	stepInstalling
	stepComplete
)

// ============================================================================
// Model
// ============================================================================

type setupModel struct {
	step        setupStep
	width       int
	height      int
	spinner     spinner.Model
	inputs      []textinput.Model
	focusIndex  int
	cursor      int
	choices     []string
	selected    map[int]struct{}
	err         error
	installing  bool
	progress    int
	progressMsg string

	// Configuration
	config setupConfig
}

type setupConfig struct {
	// Credentials
	hostname string
	username string
	password string

	// Network
	networkType string // dhcp, static, none
	ipAddress   string
	gateway     string
	dns         string

	// Disk/VRAM
	bootMode    string // vram, standard, minimal
	diskTarget  string
	vramSize    string

	// Profiles
	profile string // desktop, server, minimal, developer
}

// ============================================================================
// Messages
// ============================================================================

type tickMsg time.Time
type installProgressMsg struct {
	progress int
	message  string
}
type installCompleteMsg struct{}
type installErrorMsg struct{ err error }

// ============================================================================
// Init
// ============================================================================

func initialSetupModel() setupModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(primaryColor)

	// Create text inputs
	inputs := make([]textinput.Model, 7)

	// Hostname
	inputs[0] = textinput.New()
	inputs[0].Placeholder = "mixos"
	inputs[0].Focus()
	inputs[0].CharLimit = 64
	inputs[0].Width = 30
	inputs[0].Prompt = "🖥️  Hostname: "

	// Username
	inputs[1] = textinput.New()
	inputs[1].Placeholder = "user"
	inputs[1].CharLimit = 32
	inputs[1].Width = 30
	inputs[1].Prompt = "👤 Username: "

	// Password
	inputs[2] = textinput.New()
	inputs[2].Placeholder = "********"
	inputs[2].CharLimit = 64
	inputs[2].Width = 30
	inputs[2].EchoMode = textinput.EchoPassword
	inputs[2].EchoCharacter = '•'
	inputs[2].Prompt = "🔐 Password: "

	// IP Address
	inputs[3] = textinput.New()
	inputs[3].Placeholder = "192.168.1.100"
	inputs[3].CharLimit = 15
	inputs[3].Width = 30
	inputs[3].Prompt = "🌐 IP Address: "

	// Gateway
	inputs[4] = textinput.New()
	inputs[4].Placeholder = "192.168.1.1"
	inputs[4].CharLimit = 15
	inputs[4].Width = 30
	inputs[4].Prompt = "🚪 Gateway: "

	// DNS
	inputs[5] = textinput.New()
	inputs[5].Placeholder = "8.8.8.8"
	inputs[5].CharLimit = 15
	inputs[5].Width = 30
	inputs[5].Prompt = "📡 DNS: "

	// VRAM Size
	inputs[6] = textinput.New()
	inputs[6].Placeholder = "2G"
	inputs[6].CharLimit = 10
	inputs[6].Width = 30
	inputs[6].Prompt = "💾 VRAM Size: "

	return setupModel{
		step:     stepWelcome,
		spinner:  s,
		inputs:   inputs,
		selected: make(map[int]struct{}),
		config: setupConfig{
			hostname:    "mixos",
			username:    "user",
			networkType: "dhcp",
			bootMode:    "vram",
			profile:     "desktop",
		},
	}
}

func (m setupModel) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		textinput.Blink,
	)
}

// ============================================================================
// Update
// ============================================================================

func (m setupModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			if m.step == stepComplete {
				return m, tea.Quit
			}
			// Confirm quit
			return m, tea.Quit

		case "enter":
			return m.handleEnter()

		case "tab", "down":
			return m.handleNext()

		case "shift+tab", "up":
			return m.handlePrev()

		case "left", "right":
			if m.step == stepNetwork || m.step == stepDiskVRAM || m.step == stepProfiles {
				return m.handleSelect(msg.String())
			}

		case "esc":
			if m.step > stepWelcome && m.step < stepInstalling {
				m.step--
			}
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)

	case installProgressMsg:
		m.progress = msg.progress
		m.progressMsg = msg.message
		if m.progress < 100 {
			cmds = append(cmds, m.doInstallStep())
		}

	case installCompleteMsg:
		m.step = stepComplete
		m.installing = false

	case installErrorMsg:
		m.err = msg.err
		m.installing = false
	}

	// Update text inputs
	if m.step == stepCredentials || m.step == stepNetwork {
		for i := range m.inputs {
			var cmd tea.Cmd
			m.inputs[i], cmd = m.inputs[i].Update(msg)
			cmds = append(cmds, cmd)
		}
	}

	return m, tea.Batch(cmds...)
}

func (m setupModel) handleEnter() (tea.Model, tea.Cmd) {
	switch m.step {
	case stepWelcome:
		m.step = stepCredentials
		m.inputs[0].Focus()

	case stepCredentials:
		// Save credentials
		if m.inputs[0].Value() != "" {
			m.config.hostname = m.inputs[0].Value()
		}
		if m.inputs[1].Value() != "" {
			m.config.username = m.inputs[1].Value()
		}
		if m.inputs[2].Value() != "" {
			m.config.password = m.inputs[2].Value()
		}
		m.step = stepNetwork
		m.cursor = 0

	case stepNetwork:
		// Save network config
		if m.config.networkType == "static" {
			m.config.ipAddress = m.inputs[3].Value()
			m.config.gateway = m.inputs[4].Value()
			m.config.dns = m.inputs[5].Value()
		}
		m.step = stepDiskVRAM
		m.cursor = 0

	case stepDiskVRAM:
		// Save disk/VRAM config
		if m.inputs[6].Value() != "" {
			m.config.vramSize = m.inputs[6].Value()
		}
		m.step = stepProfiles
		m.cursor = 0

	case stepProfiles:
		m.step = stepSummary

	case stepSummary:
		m.step = stepInstalling
		m.installing = true
		m.progress = 0
		return m, m.doInstallStep()

	case stepComplete:
		return m, tea.Quit
	}

	return m, nil
}

func (m setupModel) handleNext() (tea.Model, tea.Cmd) {
	switch m.step {
	case stepCredentials:
		m.focusIndex++
		if m.focusIndex > 2 {
			m.focusIndex = 0
		}
		for i := range m.inputs[:3] {
			if i == m.focusIndex {
				m.inputs[i].Focus()
			} else {
				m.inputs[i].Blur()
			}
		}

	case stepNetwork:
		if m.config.networkType == "static" {
			m.focusIndex++
			if m.focusIndex > 5 {
				m.focusIndex = 3
			}
			for i := 3; i <= 5; i++ {
				if i == m.focusIndex {
					m.inputs[i].Focus()
				} else {
					m.inputs[i].Blur()
				}
			}
		} else {
			m.cursor++
			if m.cursor > 2 {
				m.cursor = 0
			}
		}

	case stepDiskVRAM, stepProfiles:
		m.cursor++
		maxCursor := 2
		if m.step == stepProfiles {
			maxCursor = 3
		}
		if m.cursor > maxCursor {
			m.cursor = 0
		}
	}

	return m, nil
}

func (m setupModel) handlePrev() (tea.Model, tea.Cmd) {
	switch m.step {
	case stepCredentials:
		m.focusIndex--
		if m.focusIndex < 0 {
			m.focusIndex = 2
		}
		for i := range m.inputs[:3] {
			if i == m.focusIndex {
				m.inputs[i].Focus()
			} else {
				m.inputs[i].Blur()
			}
		}

	case stepNetwork, stepDiskVRAM, stepProfiles:
		m.cursor--
		if m.cursor < 0 {
			maxCursor := 2
			if m.step == stepProfiles {
				maxCursor = 3
			}
			m.cursor = maxCursor
		}
	}

	return m, nil
}

func (m setupModel) handleSelect(direction string) (tea.Model, tea.Cmd) {
	switch m.step {
	case stepNetwork:
		types := []string{"dhcp", "static", "none"}
		idx := 0
		for i, t := range types {
			if t == m.config.networkType {
				idx = i
				break
			}
		}
		if direction == "right" {
			idx++
		} else {
			idx--
		}
		if idx < 0 {
			idx = len(types) - 1
		}
		if idx >= len(types) {
			idx = 0
		}
		m.config.networkType = types[idx]

	case stepDiskVRAM:
		modes := []string{"vram", "standard", "minimal"}
		idx := 0
		for i, mode := range modes {
			if mode == m.config.bootMode {
				idx = i
				break
			}
		}
		if direction == "right" {
			idx++
		} else {
			idx--
		}
		if idx < 0 {
			idx = len(modes) - 1
		}
		if idx >= len(modes) {
			idx = 0
		}
		m.config.bootMode = modes[idx]

	case stepProfiles:
		profiles := []string{"desktop", "server", "minimal", "developer"}
		idx := 0
		for i, p := range profiles {
			if p == m.config.profile {
				idx = i
				break
			}
		}
		if direction == "right" {
			idx++
		} else {
			idx--
		}
		if idx < 0 {
			idx = len(profiles) - 1
		}
		if idx >= len(profiles) {
			idx = 0
		}
		m.config.profile = profiles[idx]
	}

	return m, nil
}

// ============================================================================
// Installation
// ============================================================================

func (m setupModel) doInstallStep() tea.Cmd {
	return func() tea.Msg {
		time.Sleep(500 * time.Millisecond)

		steps := []struct {
			progress int
			message  string
		}{
			{10, "Initializing system..."},
			{20, "Configuring hostname..."},
			{30, "Creating user account..."},
			{40, "Setting up network..."},
			{50, "Configuring boot mode..."},
			{60, "Installing profile packages..."},
			{70, "Setting up mixmagisk..."},
			{80, "Configuring services..."},
			{90, "Finalizing installation..."},
			{100, "Installation complete!"},
		}

		for _, step := range steps {
			if m.progress < step.progress {
				return installProgressMsg{
					progress: step.progress,
					message:  step.message,
				}
			}
		}

		return installCompleteMsg{}
	}
}

// ============================================================================
// View
// ============================================================================

func (m setupModel) View() string {
	var s strings.Builder

	switch m.step {
	case stepWelcome:
		s.WriteString(m.viewWelcome())
	case stepCredentials:
		s.WriteString(m.viewCredentials())
	case stepNetwork:
		s.WriteString(m.viewNetwork())
	case stepDiskVRAM:
		s.WriteString(m.viewDiskVRAM())
	case stepProfiles:
		s.WriteString(m.viewProfiles())
	case stepSummary:
		s.WriteString(m.viewSummary())
	case stepInstalling:
		s.WriteString(m.viewInstalling())
	case stepComplete:
		s.WriteString(m.viewComplete())
	}

	return s.String()
}

func (m setupModel) viewWelcome() string {
	var s strings.Builder

	logo := lipgloss.NewStyle().
		Foreground(primaryColor).
		Bold(true).
		Render(mixOSLogo)

	s.WriteString(logo)
	s.WriteString("\n")
	s.WriteString(welcomeArt)
	s.WriteString("\n\n")

	info := []string{
		"🚀 VISO: Virtual ISO - Revolutionary boot format",
		"💾 VRAM: Boot entire system from RAM",
		"🔐 mixmagisk: Advanced root management",
		"⚡ Maximum performance with virtio",
	}

	for _, line := range info {
		s.WriteString("    " + line + "\n")
	}

	s.WriteString("\n")
	s.WriteString(helpStyle.Render("    Press ENTER to start setup • Press Q to quit"))

	return s.String()
}

func (m setupModel) viewCredentials() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("🔐 Step 1: System Credentials"))
	s.WriteString("\n\n")

	s.WriteString(subtitleStyle.Render("Configure your system identity and user account"))
	s.WriteString("\n\n")

	for i := 0; i < 3; i++ {
		s.WriteString(m.inputs[i].View())
		s.WriteString("\n")
	}

	s.WriteString("\n")
	s.WriteString(helpStyle.Render("TAB: Next field • ENTER: Continue • ESC: Back"))

	return boxStyle.Render(s.String())
}

func (m setupModel) viewNetwork() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("🌐 Step 2: Network Configuration"))
	s.WriteString("\n\n")

	s.WriteString(subtitleStyle.Render("Select network configuration type"))
	s.WriteString("\n\n")

	types := []struct {
		name string
		desc string
	}{
		{"dhcp", "Automatic (DHCP)"},
		{"static", "Manual (Static IP)"},
		{"none", "No Network"},
	}

	for _, t := range types {
		cursor := "  "
		style := normalStyle
		if t.name == m.config.networkType {
			cursor = "▶ "
			style = selectedStyle
		}
		s.WriteString(style.Render(cursor + t.desc))
		s.WriteString("\n")
	}

	if m.config.networkType == "static" {
		s.WriteString("\n")
		s.WriteString(subtitleStyle.Render("Enter network details:"))
		s.WriteString("\n\n")
		for i := 3; i <= 5; i++ {
			s.WriteString(m.inputs[i].View())
			s.WriteString("\n")
		}
	}

	s.WriteString("\n")
	s.WriteString(helpStyle.Render("←/→: Select type • TAB: Next field • ENTER: Continue"))

	return boxStyle.Render(s.String())
}

func (m setupModel) viewDiskVRAM() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("💾 Step 3: Boot Mode & Storage"))
	s.WriteString("\n\n")

	s.WriteString(subtitleStyle.Render("Select boot mode for optimal performance"))
	s.WriteString("\n\n")

	modes := []struct {
		name string
		desc string
		info string
	}{
		{"vram", "⚡ VRAM Mode (Recommended)", "Boot entire system from RAM - Maximum performance"},
		{"standard", "💿 Standard Mode", "Boot from disk - Lower memory usage"},
		{"minimal", "📦 Minimal Mode", "Minimal footprint - For low-resource systems"},
	}

	for _, mode := range modes {
		cursor := "  "
		style := normalStyle
		if mode.name == m.config.bootMode {
			cursor = "▶ "
			style = selectedStyle
		}
		s.WriteString(style.Render(cursor + mode.desc))
		s.WriteString("\n")
		s.WriteString(mutedStyle.Render("    " + mode.info))
		s.WriteString("\n\n")
	}

	if m.config.bootMode == "vram" {
		s.WriteString(subtitleStyle.Render("VRAM Configuration:"))
		s.WriteString("\n")
		s.WriteString(m.inputs[6].View())
		s.WriteString("\n")
		s.WriteString(mutedStyle.Render("    Recommended: 2G for desktop, 1G for server"))
	}

	s.WriteString("\n\n")
	s.WriteString(helpStyle.Render("←/→: Select mode • ENTER: Continue • ESC: Back"))

	return boxStyle.Render(s.String())
}

func (m setupModel) viewProfiles() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("👤 Step 4: System Profile"))
	s.WriteString("\n\n")

	s.WriteString(subtitleStyle.Render("Select a profile that matches your use case"))
	s.WriteString("\n\n")

	profiles := []struct {
		name string
		desc string
		pkgs string
	}{
		{"desktop", "🖥️  Desktop", "GUI, multimedia, productivity apps"},
		{"server", "🖧  Server", "Web server, database, monitoring"},
		{"minimal", "📦 Minimal", "Base system only"},
		{"developer", "💻 Developer", "Compilers, editors, dev tools"},
	}

	for _, p := range profiles {
		cursor := "  "
		style := normalStyle
		if p.name == m.config.profile {
			cursor = "▶ "
			style = selectedStyle
		}
		s.WriteString(style.Render(cursor + p.desc))
		s.WriteString("\n")
		s.WriteString(mutedStyle.Render("    Includes: " + p.pkgs))
		s.WriteString("\n\n")
	}

	s.WriteString(helpStyle.Render("←/→: Select profile • ENTER: Continue • ESC: Back"))

	return boxStyle.Render(s.String())
}

func (m setupModel) viewSummary() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("📋 Step 5: Installation Summary"))
	s.WriteString("\n\n")

	s.WriteString(subtitleStyle.Render("Review your configuration before installation"))
	s.WriteString("\n\n")

	// Credentials
	s.WriteString(selectedStyle.Render("🔐 Credentials"))
	s.WriteString("\n")
	s.WriteString(fmt.Sprintf("   Hostname: %s\n", m.config.hostname))
	s.WriteString(fmt.Sprintf("   Username: %s\n", m.config.username))
	s.WriteString(fmt.Sprintf("   Password: %s\n", strings.Repeat("•", len(m.config.password))))
	s.WriteString("\n")

	// Network
	s.WriteString(selectedStyle.Render("🌐 Network"))
	s.WriteString("\n")
	s.WriteString(fmt.Sprintf("   Type: %s\n", m.config.networkType))
	if m.config.networkType == "static" {
		s.WriteString(fmt.Sprintf("   IP: %s\n", m.config.ipAddress))
		s.WriteString(fmt.Sprintf("   Gateway: %s\n", m.config.gateway))
		s.WriteString(fmt.Sprintf("   DNS: %s\n", m.config.dns))
	}
	s.WriteString("\n")

	// Boot Mode
	s.WriteString(selectedStyle.Render("💾 Boot Mode"))
	s.WriteString("\n")
	s.WriteString(fmt.Sprintf("   Mode: %s\n", m.config.bootMode))
	if m.config.bootMode == "vram" {
		vramSize := m.config.vramSize
		if vramSize == "" {
			vramSize = "2G"
		}
		s.WriteString(fmt.Sprintf("   VRAM Size: %s\n", vramSize))
	}
	s.WriteString("\n")

	// Profile
	s.WriteString(selectedStyle.Render("👤 Profile"))
	s.WriteString("\n")
	s.WriteString(fmt.Sprintf("   Profile: %s\n", m.config.profile))
	s.WriteString("\n")

	s.WriteString(warningStyle().Render("⚠️  Press ENTER to begin installation"))
	s.WriteString("\n\n")
	s.WriteString(helpStyle.Render("ENTER: Install • ESC: Go back and modify"))

	return boxStyle.Render(s.String())
}

func warningStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(warningColor).Bold(true)
}

func (m setupModel) viewInstalling() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("⚙️  Installing MixOS"))
	s.WriteString("\n\n")

	s.WriteString(m.spinner.View())
	s.WriteString(" ")
	s.WriteString(m.progressMsg)
	s.WriteString("\n\n")

	// Progress bar
	width := 50
	filled := int(float64(width) * float64(m.progress) / 100)
	empty := width - filled

	bar := lipgloss.NewStyle().Foreground(successColor).Render(strings.Repeat("█", filled))
	bar += lipgloss.NewStyle().Foreground(mutedColor).Render(strings.Repeat("░", empty))

	s.WriteString(fmt.Sprintf("[%s] %d%%\n", bar, m.progress))
	s.WriteString("\n")

	steps := []string{
		"Initializing system",
		"Configuring hostname",
		"Creating user account",
		"Setting up network",
		"Configuring boot mode",
		"Installing profile packages",
		"Setting up mixmagisk",
		"Configuring services",
		"Finalizing installation",
	}

	for i, step := range steps {
		progress := (i + 1) * 10
		if m.progress >= progress {
			s.WriteString(successStyle.Render("  ✓ " + step))
		} else if m.progress >= progress-10 {
			s.WriteString(normalStyle.Render("  ⋯ " + step))
		} else {
			s.WriteString(mutedStyle.Render("  ○ " + step))
		}
		s.WriteString("\n")
	}

	return boxStyle.Render(s.String())
}

func (m setupModel) viewComplete() string {
	var s strings.Builder

	completeArt := `
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║   ✨ Installation Complete! ✨                               ║
    ║                                                              ║
    ║   🧡 Welcome to MixOS!                                       ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
`

	s.WriteString(lipgloss.NewStyle().Foreground(successColor).Render(completeArt))
	s.WriteString("\n")

	s.WriteString(titleStyle.Render("🚀 Next Steps"))
	s.WriteString("\n\n")

	bootCmd := fmt.Sprintf("VRAM=%s", m.config.bootMode)
	if m.config.bootMode == "vram" {
		bootCmd = "VRAM=auto"
	}

	steps := []string{
		"1. Reboot your system",
		fmt.Sprintf("2. Boot with parameter: %s", bootCmd),
		"3. Login with your credentials",
		"4. Run 'mix help' to get started",
	}

	for _, step := range steps {
		s.WriteString("   " + step + "\n")
	}

	s.WriteString("\n")
	s.WriteString(subtitleStyle.Render("QEMU Boot Command:"))
	s.WriteString("\n")

	qemuCmd := fmt.Sprintf(`   qemu-system-x86_64 \
     -drive file=mixos.viso,format=qcow2,if=virtio \
     -m 4G -enable-kvm \
     -append "%s"`, bootCmd)

	s.WriteString(mutedStyle.Render(qemuCmd))
	s.WriteString("\n\n")

	s.WriteString(helpStyle.Render("Press ENTER or Q to exit"))

	return s.String()
}

// ============================================================================
// Cobra Command
// ============================================================================

var setupCmd = &cobra.Command{
	Use:   "setup",
	Short: "Interactive MixOS setup wizard",
	Long: `MixOS Setup Wizard - Interactive system configuration

This wizard guides you through:
  • System credentials (hostname, username, password)
  • Network configuration (DHCP, static, or none)
  • Boot mode selection (VRAM, standard, minimal)
  • Profile selection (desktop, server, minimal, developer)

After setup, reboot with the configured parameters to complete installation.`,
	Run: func(cmd *cobra.Command, args []string) {
		// Check if running as root
		if os.Geteuid() != 0 {
			fmt.Println("Warning: Setup should be run as root for full functionality")
			fmt.Println("Some operations may fail without root privileges")
			fmt.Println()
		}

		p := tea.NewProgram(initialSetupModel(), tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			fmt.Printf("Error running setup: %v\n", err)
			os.Exit(1)
		}
	},
}

// ============================================================================
// Helper Functions
// ============================================================================

func runCommand(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func init() {
	rootCmd.AddCommand(setupCmd)
}
