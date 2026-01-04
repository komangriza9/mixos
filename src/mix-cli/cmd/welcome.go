package cmd

import (
	"fmt"
	"math/rand"
	"os"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
)

// ============================================================================
// Welcome Screen ASCII Art
// ============================================================================

const welcomeLogo = `
    ███╗   ███╗██╗██╗  ██╗ ██████╗ ███████╗
    ████╗ ████║██║╚██╗██╔╝██╔═══██╗██╔════╝
    ██╔████╔██║██║ ╚███╔╝ ██║   ██║███████╗
    ██║╚██╔╝██║██║ ██╔██╗ ██║   ██║╚════██║
    ██║ ╚═╝ ██║██║██╔╝ ██╗╚██████╔╝███████║
    ╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
`

const welcomeHeart = `
       ♥♥♥     ♥♥♥
     ♥♥   ♥♥ ♥♥   ♥♥
    ♥♥      ♥      ♥♥
     ♥♥    🧡    ♥♥
       ♥♥      ♥♥
         ♥♥  ♥♥
           ♥♥
`

const welcomeBox = `
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                        🧡 Welcome to MixOS! 🧡                               ║
║                                                                              ║
║                    Revolutionary Operating System                            ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
`

// ============================================================================
// Animation Frames
// ============================================================================

var loadingFrames = []string{
	"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
}

var heartFrames = []string{
	"🧡", "💛", "💚", "💙", "💜", "🤍", "💜", "💙", "💚", "💛",
}

var sparkleFrames = []string{
	"✨", "⭐", "🌟", "💫", "⭐", "✨",
}

// ============================================================================
// Welcome Model
// ============================================================================

type welcomePhase int

const (
	phaseLoading welcomePhase = iota
	phaseLogo
	phaseHeart
	phaseInfo
	phaseHelp
	phaseReady
)

type welcomeModel struct {
	phase       welcomePhase
	width       int
	height      int
	spinner     spinner.Model
	frame       int
	heartFrame  int
	sparkles    []sparkle
	tips        []string
	currentTip  int
	showCursor  bool
	username    string
	hostname    string
	bootMode    string
	vramEnabled bool
}

type sparkle struct {
	x, y   int
	char   string
	active bool
}

type welcomeTickMsg time.Time
type phaseMsg welcomePhase

func welcomeTickCmd() tea.Cmd {
	return tea.Tick(100*time.Millisecond, func(t time.Time) tea.Msg {
		return welcomeTickMsg(t)
	})
}

func nextPhaseCmd(phase welcomePhase, delay time.Duration) tea.Cmd {
	return tea.Tick(delay, func(t time.Time) tea.Msg {
		return phaseMsg(phase)
	})
}

// ============================================================================
// Init
// ============================================================================

func initialWelcomeModel() welcomeModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(primaryColor)

	// Get system info
	hostname, _ := os.Hostname()
	username := os.Getenv("USER")
	if username == "" {
		username = "user"
	}

	// Check boot mode
	bootMode := "Standard"
	vramEnabled := false
	if _, err := os.Stat("/run/mixos/vram"); err == nil {
		bootMode = "VRAM"
		vramEnabled = true
	}

	tips := []string{
		"💡 Tip: Use 'mix help' to see all available commands",
		"💡 Tip: Use 'mix search <package>' to find packages",
		"💡 Tip: Use 'mixmagisk' for root operations",
		"💡 Tip: Press Ctrl+C to exit any command",
		"💡 Tip: Use 'mix vram status' to check VRAM mode",
		"💡 Tip: Use 'mix update' to refresh package database",
	}

	// Generate random sparkles
	sparkles := make([]sparkle, 20)
	for i := range sparkles {
		sparkles[i] = sparkle{
			x:      rand.Intn(80),
			y:      rand.Intn(24),
			char:   sparkleFrames[rand.Intn(len(sparkleFrames))],
			active: rand.Float32() > 0.5,
		}
	}

	return welcomeModel{
		phase:       phaseLoading,
		spinner:     s,
		tips:        tips,
		sparkles:    sparkles,
		username:    username,
		hostname:    hostname,
		bootMode:    bootMode,
		vramEnabled: vramEnabled,
	}
}

func (m welcomeModel) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		welcomeTickCmd(),
		nextPhaseCmd(phaseLogo, 1*time.Second),
	)
}

// ============================================================================
// Update
// ============================================================================

func (m welcomeModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "enter", " ":
			if m.phase == phaseReady {
				return m, tea.Quit
			}
			// Skip to ready phase
			m.phase = phaseReady
		case "?", "h":
			// Show help
			m.phase = phaseHelp
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)

	case welcomeTickMsg:
		m.frame++
		m.heartFrame = (m.heartFrame + 1) % len(heartFrames)
		m.showCursor = !m.showCursor
		m.currentTip = (m.frame / 30) % len(m.tips)

		// Update sparkles
		for i := range m.sparkles {
			if rand.Float32() > 0.9 {
				m.sparkles[i].active = !m.sparkles[i].active
			}
			if rand.Float32() > 0.95 {
				m.sparkles[i].char = sparkleFrames[rand.Intn(len(sparkleFrames))]
			}
		}

		cmds = append(cmds, welcomeTickCmd())

	case phaseMsg:
		m.phase = welcomePhase(msg)
		switch m.phase {
		case phaseLogo:
			cmds = append(cmds, nextPhaseCmd(phaseHeart, 1500*time.Millisecond))
		case phaseHeart:
			cmds = append(cmds, nextPhaseCmd(phaseInfo, 1500*time.Millisecond))
		case phaseInfo:
			cmds = append(cmds, nextPhaseCmd(phaseReady, 2*time.Second))
		}
	}

	return m, tea.Batch(cmds...)
}

// ============================================================================
// View
// ============================================================================

func (m welcomeModel) View() string {
	var s strings.Builder

	switch m.phase {
	case phaseLoading:
		s.WriteString(m.viewLoading())
	case phaseLogo:
		s.WriteString(m.viewLogo())
	case phaseHeart:
		s.WriteString(m.viewHeart())
	case phaseInfo:
		s.WriteString(m.viewInfo())
	case phaseHelp:
		s.WriteString(m.viewHelp())
	case phaseReady:
		s.WriteString(m.viewReady())
	}

	return s.String()
}

func (m welcomeModel) viewLoading() string {
	var s strings.Builder

	// Center the loading animation
	s.WriteString("\n\n\n\n\n")

	loadingText := fmt.Sprintf("    %s Initializing MixOS...", m.spinner.View())
	s.WriteString(lipgloss.NewStyle().Foreground(primaryColor).Render(loadingText))
	s.WriteString("\n\n")

	// Animated dots
	dots := strings.Repeat(".", (m.frame%4)+1)
	s.WriteString(lipgloss.NewStyle().Foreground(mutedColor).Render("    " + dots))

	return s.String()
}

func (m welcomeModel) viewLogo() string {
	var s strings.Builder

	// Animated logo reveal
	logo := welcomeLogo
	lines := strings.Split(logo, "\n")

	revealedLines := (m.frame % 10) + 1
	if revealedLines > len(lines) {
		revealedLines = len(lines)
	}

	for i := 0; i < revealedLines && i < len(lines); i++ {
		color := primaryColor
		if i%2 == 0 {
			color = secondaryColor
		}
		s.WriteString(lipgloss.NewStyle().Foreground(color).Bold(true).Render(lines[i]))
		s.WriteString("\n")
	}

	return s.String()
}

func (m welcomeModel) viewHeart() string {
	var s strings.Builder

	// Logo
	s.WriteString(lipgloss.NewStyle().Foreground(primaryColor).Bold(true).Render(welcomeLogo))
	s.WriteString("\n")

	// Animated heart
	heart := heartFrames[m.heartFrame]
	heartLine := fmt.Sprintf("                              %s Welcome! %s", heart, heart)
	s.WriteString(lipgloss.NewStyle().Foreground(successColor).Bold(true).Render(heartLine))
	s.WriteString("\n\n")

	return s.String()
}

func (m welcomeModel) viewInfo() string {
	var s strings.Builder

	// Logo
	s.WriteString(lipgloss.NewStyle().Foreground(primaryColor).Bold(true).Render(welcomeLogo))
	s.WriteString("\n")

	// Welcome box
	s.WriteString(lipgloss.NewStyle().Foreground(secondaryColor).Render(welcomeBox))
	s.WriteString("\n")

	// System info
	infoStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))
	labelStyle := lipgloss.NewStyle().Foreground(primaryColor).Bold(true)

	s.WriteString(labelStyle.Render("    👤 User: "))
	s.WriteString(infoStyle.Render(m.username))
	s.WriteString("\n")

	s.WriteString(labelStyle.Render("    🖥️  Host: "))
	s.WriteString(infoStyle.Render(m.hostname))
	s.WriteString("\n")

	s.WriteString(labelStyle.Render("    ⚡ Mode: "))
	modeStyle := infoStyle
	if m.vramEnabled {
		modeStyle = lipgloss.NewStyle().Foreground(successColor).Bold(true)
	}
	s.WriteString(modeStyle.Render(m.bootMode))
	s.WriteString("\n")

	return s.String()
}

func (m welcomeModel) viewHelp() string {
	var s strings.Builder

	s.WriteString(titleStyle.Render("📖 MixOS Quick Help"))
	s.WriteString("\n\n")

	commands := []struct {
		cmd  string
		desc string
	}{
		{"mix help", "Show all available commands"},
		{"mix search <pkg>", "Search for packages"},
		{"mix install <pkg>", "Install a package"},
		{"mix remove <pkg>", "Remove a package"},
		{"mix update", "Update package database"},
		{"mix list", "List installed packages"},
		{"mix vram status", "Check VRAM mode status"},
		{"mix viso info", "Show VISO information"},
		{"mixmagisk <cmd>", "Run command as root"},
	}

	for _, c := range commands {
		s.WriteString(selectedStyle.Render("  " + c.cmd))
		s.WriteString("\n")
		s.WriteString(mutedStyle.Render("    " + c.desc))
		s.WriteString("\n\n")
	}

	s.WriteString(helpStyle.Render("Press ENTER to continue • Press Q to exit"))

	return boxStyle.Render(s.String())
}

func (m welcomeModel) viewReady() string {
	var s strings.Builder

	// Add some sparkles
	sparkleLayer := make([][]rune, 24)
	for i := range sparkleLayer {
		sparkleLayer[i] = make([]rune, 80)
		for j := range sparkleLayer[i] {
			sparkleLayer[i][j] = ' '
		}
	}
	for _, sp := range m.sparkles {
		if sp.active && sp.y < 24 && sp.x < 80 {
			sparkleLayer[sp.y][sp.x] = []rune(sp.char)[0]
		}
	}

	// Logo with animation
	s.WriteString(lipgloss.NewStyle().Foreground(primaryColor).Bold(true).Render(welcomeLogo))
	s.WriteString("\n")

	// Welcome message with animated heart
	heart := heartFrames[m.heartFrame]
	welcomeMsg := fmt.Sprintf("    %s Welcome to MixOS, %s! %s", heart, m.username, heart)
	s.WriteString(lipgloss.NewStyle().Foreground(successColor).Bold(true).Render(welcomeMsg))
	s.WriteString("\n\n")

	// System status
	statusBox := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(secondaryColor).
		Padding(0, 2)

	var status strings.Builder
	status.WriteString(lipgloss.NewStyle().Foreground(primaryColor).Bold(true).Render("System Status"))
	status.WriteString("\n")

	// Boot mode indicator
	modeIcon := "💿"
	modeColor := lipgloss.Color("#FFFFFF")
	if m.vramEnabled {
		modeIcon = "⚡"
		modeColor = successColor
	}
	status.WriteString(fmt.Sprintf("  %s Boot Mode: ", modeIcon))
	status.WriteString(lipgloss.NewStyle().Foreground(modeColor).Bold(true).Render(m.bootMode))
	status.WriteString("\n")

	// Hostname
	status.WriteString(fmt.Sprintf("  🖥️  Hostname: %s\n", m.hostname))

	// User
	status.WriteString(fmt.Sprintf("  👤 User: %s\n", m.username))

	s.WriteString(statusBox.Render(status.String()))
	s.WriteString("\n\n")

	// Animated tip
	tipStyle := lipgloss.NewStyle().
		Foreground(warningColor).
		Italic(true)
	s.WriteString(tipStyle.Render("    " + m.tips[m.currentTip]))
	s.WriteString("\n\n")

	// Quick commands
	s.WriteString(lipgloss.NewStyle().Foreground(secondaryColor).Bold(true).Render("    Quick Commands:"))
	s.WriteString("\n")
	s.WriteString(mutedStyle.Render("    • mix help     - Show all commands"))
	s.WriteString("\n")
	s.WriteString(mutedStyle.Render("    • mix search   - Find packages"))
	s.WriteString("\n")
	s.WriteString(mutedStyle.Render("    • mixmagisk    - Root operations"))
	s.WriteString("\n\n")

	// Cursor animation
	cursor := " "
	if m.showCursor {
		cursor = "▌"
	}
	prompt := fmt.Sprintf("    %s@%s:~$ %s", m.username, m.hostname, cursor)
	s.WriteString(lipgloss.NewStyle().Foreground(successColor).Render(prompt))
	s.WriteString("\n\n")

	s.WriteString(helpStyle.Render("    Press ENTER to start • Press ? for help • Press Q to exit"))

	return s.String()
}

// ============================================================================
// Cobra Command
// ============================================================================

var welcomeCmd = &cobra.Command{
	Use:   "welcome",
	Short: "Show MixOS welcome screen",
	Long: `Display the MixOS welcome screen with animations.

This screen is shown after first boot and provides:
  • System status information
  • Quick command reference
  • Helpful tips for getting started

The welcome screen features animated elements and provides
a warm greeting to new MixOS users.`,
	Run: func(cmd *cobra.Command, args []string) {
		p := tea.NewProgram(initialWelcomeModel(), tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			fmt.Printf("Error: %v\n", err)
			os.Exit(1)
		}
	},
}

func init() {
	rootCmd.AddCommand(welcomeCmd)
}
