import Foundation
import StickyMCP

// stdout carries only JSON-RPC; everything else is logged to stderr.
exit(await StickyMCPMain.run())
