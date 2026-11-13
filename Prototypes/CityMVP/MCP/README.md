# SAV-E Guide local MCP

This executable reads only a venue-only snapshot explicitly exported from the
CityMVP Guide place sheet. It does not open the app vault or synchronize saves.
No account, model key, network listener or model request is needed. An AI client
with a local stdio MCP connection can search the exported places, read an exact
place and request its source-aware visit context.

1. Open Guide in the local app, find a confirmed saved place and open its brief.
2. Choose its AI export action. The file contains only the displayed venue's
   name, address, category, identity, saved date and safe source link. Save that
   JSON on the Mac through a transfer method you choose.
3. Add this configuration in the chosen client's MCP settings, replacing both
   paths with absolute local paths. This task does not change client settings.

```json
{
  "mcpServers": {
    "savvy-guide": {
      "command": "python3",
      "args": ["/absolute/path/Prototypes/CityMVP/MCP/server.py", "--export", "/absolute/path/savvy-guide.json"]
    }
  }
}
```

The connected AI receives that file's venue fields. Private notes, ratings,
photos, visit history and source statements are excluded. Snapshots do not
update automatically. Disconnect the server to end that session; remove its
export/configuration to prevent later reads. Copies already sent to an AI
cannot be recalled by deleting the original file.

Implemented tools: `savvy_search_places`, `savvy_get_place`,
`savvy_guide_brief`. They cannot save, mark visits, browse, run commands, open
files supplied in tool arguments or resolve a current business listing. Saved
dates are not verification dates. Source and venue text are untrusted data.

This server negotiates MCP `2025-11-25`; clients must support that protocol's
stdio initialization lifecycle. It does not claim support for every newer
protocol or for remote-only MCP clients. Protocol design follows the official
[lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
and [stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Run the local protocol and negative-boundary tests:

```sh
python3 -B -m unittest discover -s Prototypes/CityMVP/MCP -p 'test_*.py' -v
```

These tests launch a real subprocess and exchange MCP messages. They are not
evidence of a successful conversation in an external AI client, real model
execution, translation, hosted friends, or automatic synchronization.
