import { Denops } from "https://deno.land/x/denops_std@v3.12.1/mod.ts";
import { batch } from "https://deno.land/x/denops_std@v3.12.1/batch/mod.ts";
import {
  map,
  MapOptions,
} from "https://deno.land/x/denops_std@v4.0.0/mapping/mod.ts";
import * as op from "https://deno.land/x/denops_std@v4.0.0/option/mod.ts";
import * as helper from "https://deno.land/x/denops_std@v4.0.0/helper/mod.ts";
import * as vars from "https://deno.land/x/denops_std@v4.0.0/variable/mod.ts";
import {
  DduOptions,
  UserSource,
} from "https://deno.land/x/ddu_vim@v2.2.0/types.ts";
import {
  Fn,
  register,
} from "https://deno.land/x/denops_std@v4.0.0/lambda/mod.ts";

export function main(denops: Denops) {
  denops.dispatcher = {
    ...denops.dispatcher,
    async ddu_setup(): Promise<void> {
      await batch(denops, async (denops) => {
        const m = async (lhs: string, rhs: string, op?: MapOptions) => {
          await map(denops, lhs, rhs, op);
        };
        await m("<Space>d", "<cmd>Ddu source<CR>");
        await m("<Space>a", "<cmd>Ddu file_external<CR>");
        await m("<Space>h", "<cmd>Ddu help<CR>");
        await m("<Space>o", "<cmd>Ddu file_old<CR>");
        await m("<Space>s", "<cmd>Ddu directory_rec<CR>");
        await m("<Space>n", "<cmd>Ddu ghq<CR>");
        await m("<Space>b", "<cmd>Ddu buffer<CR>");
        await m("<Space>r", "<cmd>Ddu -resume<CR>");
        await m("<Space>g", "<cmd>DduRgLive<CR>");
        await m("<Space>m", "<cmd>Ddu man<CR>");
        await m(
          "<Space>f",
          "<cmd>Ddu file_external -source-option-path=~/dotfiles<CR>",
        );
        await m("g0", "<cmd>LspDocumentSymbols<CR>");
        await m(
          "<C-t>",
          `"<C-u><ESC><cmd>Ddu command_history -input='" . getcmdline() . "'<CR>"`,
          { mode: "c", expr: true, silent: true },
        );

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
          ui: "ff",
          profile: false,
          sourceOptions: {
            _: { ignoreCase: true, matchers: ["matcher_fzy"] },
            dein: { defaultAction: "cd" },
            line: { matchers: ["matcher_kensaku"] },
            highlight: { defaultAction: "edit" },
            help: { defaultAction: "open" },
            file_external: { defaultAction: "open" },
            directory_rec: { defaultAction: "cd" },
            man: { defaultAction: "open" },
            ghq: { defaultAction: "cd", path: "~" },
            command_history: { defaultAction: "execute" },
            dein_update: { matchers: ["matcher_dein_update"] },
            nvim_lsp_document_symbol: { columns: ["lsp_symbols"] },
          },
          kindOptions: {
            file: { defaultAction: "open" },
            action: { defaultAction: "do" },
            dein_update: { defaultAction: "viewDiff" },
            gin_action: { defaultAction: "execute" },
            source: { defaultAction: "execute" },
            ui_select: { defaultAction: "select" },
          },
          actionOptions: {
            echo: { quit: false },
            echoDiff: { quit: false },
            newFile: { quit: false },
            newDirectory: { quit: false },
            narrow: { quit: false },
          },
          filterParams: {
            matcher_fzy: { hlGroup: "Special" },
            matcher_kensaku: { highlightMatched: "Search" },
          },
          sourceParams: {
            file_external: {
              cmd: [
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
            directory_rec: {
              cmd: [
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
            rg: {
              args: ["--json", "--ignore-case"],
              highlights: {
                path: "SpecialComment",
                lineNr: "LineNr",
                word: "Constant",
              },
            },
            ghq: { cmd: ["ghq", "list", "-p"] },
          },
          uiParams: {
            ff: {
              split: denops.meta.host == "nvim" ? "floating" : "horizontal",
              filterSplitDirection: "floating",
              filterFloatingPosition: "top",
              ignoreEmpty: true,
              autoResize: true,
            },
            filer: { split: "no" },
          },
          columnParams: {
            lsp_symbols: {
              collapsedIcon: "",
              expandedIcon: "",
              iconWidth: 4,
              kindLabels: {
                File: "",
                Module: "",
                Namespace: "",
                Class: ["", "Special"],
                Method: ["", "Special"],
                Text: "",
                Function: ["", "Special"],
                Constructor: ["", "Special"],
                Field: "",
                Variable: "",
                Interface: "",
                Property: "",
                Unit: "",
                Value: "",
                Enum: "",
                Keyword: "",
                Snippet: "",
                Color: "",
                Reference: "",
                Folder: "",
                Constant: "",
                EnumMember: "",
                Struct: "",
                Event: "",
                Operator: "",
                TypeParameter: "",
              },
            },
          },
        });
      });
      const registerCommand = async (command: string, fn: Fn) => {
        const id = register(denops, fn);
        await denops.cmd(
          `command! ${command} call denops#request('vimrc', '${id}', [])`,
        );
      };
      const start = async (dict: Partial<DduOptions>) => {
        await denops.call("ddu#start", dict);
      };
      const dduWithPreview = async (
        sources: UserSource[],
        volatile: boolean,
      ) => {
        const column = await op.columns.get(denops);
        const line = await denops.eval("&lines") as number;
        const winHeight = Math.min(line - 10, 45);
        const winRow = (line - winHeight) / 2;

        const winWidth = Math.min(column / 2 - 5, 80);
        const winCol = column / 2 - winWidth;
        await start({
          sources: sources,
          volatile: true,
          uiParams: {
            ff: {
              split: denops.meta.host == "nvim" ? "floating" : "horizontal",
              autoAction: { name: "preview", delay: 50 },
              filterSplitDirection: "floating",
              filterFloatingPosition: "top",
              previewFloating: true,
              previewSplit: "vertical",
              previewHeight: winHeight,
              previewWidth: winWidth,
              winCol: winCol,
              winRow: winRow,
              winWidth: winWidth,
              winHeight: winHeight,
              ignoreEmpty: !volatile,
              autoResize: false,
            },
          },
        });
      };
      await registerCommand("DduRgLive", async () => {
        await dduWithPreview([{ name: "rg", options: { matchers: [] } }], true);
      });
      await registerCommand("DeinUpdate", async () => {
        await dduWithPreview([{ name: "dein_update" }], false);
      });
      await registerCommand("LspDocumentSymbols", async () => {
        await dduWithPreview([{ name: "nvim_lsp_document_symbol" }], false);
      });
      await registerCommand("DduRgPreview", async () => {
        const input = await helper.input(denops, { prompt: "Pattern: " });
        if (input == null) return;
        await dduWithPreview([{ name: "rg", params: { input: input } }], false);
      });
      await registerCommand("DduRgGlob", async () => {
        const pattern = await helper.input(denops, {
          prompt: "search pattern: ",
        });
        if (pattern == null) return;
        const glob = await helper.input(denops, {
          prompt: "glob pattern: ",
        });
        if (glob == null) return;
        const args = ["--json", "--ignore-case"];
        if (glob) {
          args.push("-g", glob);
        }
        await start({
          sources: [{ name: "rg", params: { input: pattern, args: args } }],
        });
      });
      await registerCommand("DduFiler", async () => {
        await start({
          ui: "filer",
          // name: 'filer-' + await fn.(),
          resume: true,
          sync: true,
          sources: [{
            name: "file",
            options: {
              path: await vars.t.get(denops, "ddu_ui_filer_path", ""),
              columns: ["filename"],
            },
          }],
          actionOptions: {
            narrow: {
              quit: false,
            },
          },
        });
      });
      return Promise.resolve();
    },
  };
}
