import { Denops } from "https://deno.land/x/denops_std@v3.12.1/mod.ts";
import { batch } from "https://deno.land/x/denops_std@v3.12.1/batch/mod.ts";
import { DduOptions } from "https://deno.land/x/ddu_vim@v2.2.0/types.ts";

export function main(denops: Denops) {
  denops.dispatcher = {
    ...denops.dispatcher,
    async ddu_setup(): Promise<void> {
      await batch(denops, async (denops) => {
        const patchGlobal = async (dict: Partial<DduOptions>) => {
          await denops.call("ddu#custom#patch_global", dict);
        };
        await denops.call(
          "ddu#custom#alias",
          "source",
          "directory_rec",
          "file_external",
        );
        await denops.call("ddu#custom#alias", "source", "ghq", "file_external");
        await patchGlobal({
          "ui": "ff",
          "profile": false,
          "sourceOptions": {
            "_": {
              "ignoreCase": true,
              "matchers": ["matcher_fzy"],
            },
            "dein": {
              "defaultAction": "cd",
            },
            "line": {
              "matchers": ["matcher_kensaku"],
            },
            "highlight": {
              "defaultAction": "edit",
            },
            "help": {
              "defaultAction": "open",
            },
            "file_external": {
              "defaultAction": "open",
            },
            "directory_rec": {
              "defaultAction": "cd",
            },
            "man": {
              "defaultAction": "open",
            },
            "ghq": {
              "defaultAction": "cd",
              "path": "~",
            },
            "command_history": {
              "defaultAction": "execute",
            },
            "dein_update": {
              "matchers": ["matcher_dein_update"],
            },
            "nvim_lsp_document_symbol": {
              "columns": ["lsp_symbols"],
            },
          },
          "kindOptions": {
            "file": {
              "defaultAction": "open",
            },
            "action": {
              "defaultAction": "do",
            },
            "dein_update": {
              "defaultAction": "viewDiff",
            },
            "gin_action": {
              "defaultAction": "execute",
            },
            "source": {
              "defaultAction": "execute",
            },
            "ui_select": {
              "defaultAction": "select",
            },
          },
          "actionOptions": {
            "echo": {
              "quit": false,
            },
            "echoDiff": {
              "quit": false,
            },
          },
          "filterParams": {
            "matcher_fzy": {
              "hlGroup": "Special",
            },
            "matcher_kensaku": {
              "highlightMatched": "Search",
            },
          },
          "sourceParams": {
            "file_external": {
              "cmd": [
                "fd",
                ".",
                "-H",
                "-E",
                ".git",
                "-E",
                "__pycache__",
                "-t",
                "f",
              ],
            },
            "directory_rec": {
              "cmd": [
                "fd",
                ".",
                "-H",
                "-E",
                ".git",
                "-E",
                "__pycache__",
                "-t",
                "d",
              ],
            },
            "rg": {
              "args": ["--json", "--ignore-case"],
              "highlights": {
                "path": "SpecialComment",
                "lineNr": "LineNr",
                "word": "Constant",
              },
            },
            "ghq": { "cmd": ["ghq", "list", "-p"] },
          },
          "uiParams": {
            "ff": {
              "split": denops.meta.host == "nvim" ? "floating" : "horizontal",
              "filterSplitDirection": "floating",
              "filterFloatingPosition": "top",
              "ignoreEmpty": true,
              "autoResize": true,
            },
            "filer": {
              "split": "no",
            },
          },
          "columnParams": {
            "lsp_symbols": {
              "collapsedIcon": "",
              "expandedIcon": "",
              "iconWidth": 4,
              "kindLabels": {
                "File": "",
                "Module": "",
                "Namespace": "",
                "Class": ["", "Special"],
                "Method": ["", "Special"],
                "Text": "",
                "Function": ["", "Special"],
                "Constructor": ["", "Special"],
                "Field": "",
                "Variable": "",
                "Interface": "",
                "Property": "",
                "Unit": "",
                "Value": "",
                "Enum": "",
                "Keyword": "",
                "Snippet": "",
                "Color": "",
                "Reference": "",
                "Folder": "",
                "Constant": "",
                "EnumMember": "",
                "Struct": "",
                "Event": "",
                "Operator": "",
                "TypeParameter": "",
              },
            },
          },
        });
      });
      return Promise.resolve();
    },
  };
}
