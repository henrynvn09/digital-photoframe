# AGENTS.md - MagicMirror Configuration Project

## Project Overview
This is a MagicMirror configuration repository for a digital photo frame using a 27-inch monitor. It runs server MM on NAS with Raspberry Pi as client.

## Build/Test Commands
- No package.json - this is a configuration-only project
- Testing: Restart MagicMirror server after config changes
- Docker command for NAS: `docker run -d --name magicmirror --publish 8036:8080 --restart unless-stopped -e TZ=America/Los_Angeles --volume /volume1/docker/magicmirror/config:/opt/magic_mirror/config --volume /volume1/docker/magicmirror/modules:/opt/magic_mirror/modules --volume /volume1/docker/magicmirror/css:/opt/magic_mirror/css karsten13/magicmirror:latest`

## Code Style Guidelines
- **JavaScript**: Use `let` instead of `var`, tabs for indentation
- **Comments**: Use `//` for single-line, `/* */` for multi-line blocks
- **Configuration**: Keep API keys empty in committed files
- **Python**: Use snake_case, proper imports, global variables declared explicitly
- **CSS**: Use kebab-case for classes, rgba for transparency, consistent spacing

## File Structure
- `config/config.js` - Main MagicMirror configuration
- `css/custom.css` - Custom styling overrides
- `pir-control-display/` - Python PIR sensor control scripts
- Shell scripts for display/mirror control in root

## Notes for Agents
- Never commit API keys or credentials
- Test configuration changes by restarting MagicMirror
- Follow existing Vietnamese text patterns for headers
- Maintain existing module positioning and styling