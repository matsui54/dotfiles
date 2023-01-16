import { Denops } from "https://deno.land/x/denops_std@v3.12.1/mod.ts";
import { batch } from "https://deno.land/x/denops_std@v3.12.1/batch/mod.ts";

export function main(denops: Denops) {
  denops.dispatcher = {
    echo(arg1: unknown): Promise<void> {
      console.log(arg1);
      return Promise.resolve();
    },
    async ddc_setup(): Promise<void> {
      await batch(denops, async (denops) => {
        const patchGlobal = async (dict: Record<string, unknown>) => {
          await denops.call("ddc#custom#patch_global", dict);
        };
        const patchFiletype = async (
          ft: string | string[],
          dict: Record<string, unknown>,
        ) => {
          await denops.call("ddc#custom#patch_filetype", ft, dict);
        };
        await patchGlobal({
          "ui": "pum",
          "sources": (denops.meta.host == "nvim"
            ? ["nvim-lsp", "buffer", "around", "vsnip", "dictionary"]
            : ["vim-lsp", "buffer", "around", "vsnip", "dictionary"]),
          "cmdlineSources": {
            ":": ["cmdline", "buffer"],
            "@": ["buffer", "input"],
            "=": ["input"],
            "/": [],
          },
          "postFilters": ["postfilter_score"],
          "autoCompleteEvents": [
            "InsertEnter",
            "TextChangedI",
            "TextChangedP",
            "CmdlineChanged",
          ],
          "specialBufferCompletion": true,
          "sourceOptions": {
            "_": {
              "matchers": ["matcher_fuzzy"],
              "sorters": ["sorter_fuzzy"],
              "converters": ["converter_remove_overlap", "converter_truncate"],
              "ignoreCase": true,
            },
            "around": { "mark": "[A]" },
            "cmdline": {
              "mark": "[cmd]",
              "forceCompletionPattern": "\\s|/|-",
              "minAutoCompleteLength": 1,
            },
            "cmdline-history": {
              "matchers": ["matcher_head"],
              "sorters": [],
              "mark": "[hist]",
              "minAutoCompleteLength": 1,
              "maxItems": 3,
            },
            "dictionary": {
              "matchers": ["matcher_editdistance"],
              "sorters": [],
              "converters": ["converter_fuzzy"],
              "maxItems": 6,
              "mark": "[D]",
              "minAutoCompleteLength": 3,
            },
            "necovim": { "mark": "[neco]", "maxItems": 6 },
            "nvim-lsp": {
              "mark": "[lsp]",
              "dup": true,
              "minAutoCompleteLength": 10000,
            },
            "vim-lsp": {
              "mark": "[lsp]",
              "dup": true,
              "forceCompletionPattern": "\\.|:\\s*|->",
              "minAutoCompleteLength": 1,
            },
            "buffer": { "mark": "[B]", "maxItems": 10 },
            "file": {
              "mark": "[F]",
              "isVolatile": true,
              "forceCompletionPattern": "\S/\S*",
              "minAutoCompleteLength": 1,
            },
            "latex-symbols": {
              "mark": "[latex]",
              "forceCompletionPattern": "\\",
            },
            "file_rec": { "mark": "[P]", "minAutoCompleteLength": 1 },
            "emoji": {
              "mark": "[emoji]",
              "dup": true,
              "matcherKey": "kind",
              "minAutoCompleteLength": 1,
            },
            "vsnip": { "mark": "[V]", "dup": true },
            "skkeleton": {
              "mark": "[skk]",
              "matchers": ["skkeleton"],
              "sorters": [],
              "isVolatile": true,
              "minAutoCompleteLength": 2,
            },
            "zsh": {
              "mark": "[Z]",
              "forceCompletionPattern": "^!.*",
              "minAutoCompleteLength": 10000,
            },
          },
          "sourceParams": {
            "around": { "maxSize": 500 },
            "file_rec": { "cmd": ["fd", "--max-depth", "5"] },
            "buffer": {
              "forceCollect": true,
              "fromAltBuf": true,
              "bufNameStyle": "basename",
            },
            "dictionary": { "smartCase": true, "showMenu": false },
            "nvim-lsp": {
              "kindLabels": {
                "Text": " Text",
                "Method": " Method",
                "Function": " Function",
                "Constructor": " Constructor",
                "Field": "ﰠ Field",
                "Variable": " Variable",
                "Class": "ﴯ Class",
                "Interface": " Interface",
                "Module": " Module",
                "Property": "ﰠ Property",
                "Unit": "塞 Unit",
                "Value": " Value",
                "Enum": " Enum",
                "Keyword": " Keyword",
                "Snippet": " Snippet",
                "Color": " Color",
                "File": " File",
                "Reference": " Reference",
                "Folder": " Folder",
                "EnumMember": " EnumMember",
                "Constant": " Constant",
                "Struct": "פּ Struct",
                "Event": " Event",
                "Operator": " Operator",
                "TypeParameter": "TypeParameter",
              },
            },
          },
          "filterParams": {
            "converter_truncate": {
              "maxAbbrWidth": 60,
              "maxInfo": 500,
              "maxMenuWidth": 0,
              "ellipsis": "...",
            },
            "converter_fuzzy": { "hlGroup": "Title" },
            "postfilter_score": {
              "excludeSources": ["dictionary", "skkeleton", "emoji"],
            },
          },
        });
        await patchFiletype(
          ["denite-filter", "ddu-ff-filter", "TelescopePrompt"],
          { "specialBufferCompletion": false },
        );
        await patchFiletype(
          ["toml"],
          {
            "sources": [
              "necovim",
              "buffer",
              "around",
              "vsnip",
              "file",
              "dictionary",
            ],
          },
        );
        await patchFiletype(
          ["zsh"],
          {
            "sources": [
              "zsh",
              "buffer",
              "around",
              "vsnip",
              "file",
              "dictionary",
            ],
          },
        );
        await patchFiletype(
          ["tex"],
          {
            "keywordPattern": "[a-zA-Z0-9_@]*",
            "sourceOptions": { "vsnip": { "forceCompletionPattern": "@" } },
          },
        );
      });
      return Promise.resolve();
    },
  };
}
