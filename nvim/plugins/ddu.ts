import * as op from "jsr:@denops/std@7.4.0/option";
import * as helper from "jsr:@denops/std@7.4.0/helper";
import * as vars from "jsr:@denops/std@7.4.0/variable";
import type { DduOptions, UserSource } from "jsr:@shougo/ddu-vim@9.4.0/types";
import {
  BaseConfig,
  type ConfigArguments,
} from "jsr:@shougo/ddu-vim@9.4.0/config";
import { Fn, register } from "jsr:@denops/std@7.4.0/lambda";
import { ensure, is } from "jsr:@core/unknownutil@4.3.0";

export class Config extends BaseConfig {
  override async config(args: ConfigArguments): Promise<void> {
    const denops = args.denops;

    args.setAlias("default", "source", "directory_rec", "file_external");
    args.setAlias("default", "source", "ghq", "file_external");
    args.contextBuilder.patchGlobal({
      ui: "ff",
      profile: false,
      sourceOptions: {
        _: { ignoreCase: true, matchers: ["matcher_fzy"] },
        dein: { defaultAction: "cd" },
        // line: { matchers: ["matcher_kensaku"] },
        highlight: { defaultAction: "edit" },
        help: { defaultAction: "open" },
        file_external: { defaultAction: "open" },
        directory_rec: { defaultAction: "cd" },
        man: { defaultAction: "open" },
        ghq: { defaultAction: "cd", path: "~" },
        command_history: { defaultAction: "execute" },
        dein_update: { matchers: ["matcher_dein_update"] },
        nvim_lsp_document_symbol: { columns: ["lsp_symbols"] },
        spec_addrs: { defaultAction: "open" },
      },
      kindOptions: {
        file: { defaultAction: "open" },
        action: { defaultAction: "do" },
        dein_update: { defaultAction: "viewDiff" },
        gin_action: { defaultAction: "execute" },
        source: { defaultAction: "execute" },
        ui_select: { defaultAction: "select" },
        lsp: { defaultAction: "open" },
        lsp_codeAction: { defaultAction: "apply" },
      },
      actionOptions: {
        echo: { quit: false },
        echoDiff: { quit: false },
        newFile: { quit: false },
        newDirectory: { quit: false },
        narrow: { quit: false },
        cd: { quit: false },
      },
      filterParams: {
        matcher_fzy: { hlGroup: "Special" },
        // matcher_kensaku: { highlightMatched: "Search" },
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
          maxHighlightItems: 1000,
        },
        filer: { split: "no", sortTreesFirst: true },
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
    const registerCommand = async (command: string, fn: Fn) => {
      const id = register(denops, fn);
      await denops.cmd(
        `command! -nargs=* ${command} call denops#request('ddu', '${id}', ["<args>"])`,
      );
    };
    const start = async (dict: Partial<DduOptions>) => {
      await denops.call("ddu#start", dict);
    };
    const dduWithPreview = async (
      sources: UserSource[],
      uiAditonalParams: Record<string, unknown> = {},
    ) => {
      const column = await op.columns.get(denops);
      const line = await op.lines.get(denops);
      const winHeight = line - 8;
      const winRow = Math.floor((line - winHeight) / 2);

      const winWidth = Math.min(Math.floor(column / 2) - 5, 120);
      const winCol = Math.floor(column / 2) - winWidth;
      await start({
        sources: sources,
        uiParams: {
          ff: Object.assign({
            split: denops.meta.host == "nvim" ? "floating" : "horizontal",
            autoAction: { name: "preview", delay: 50 },
            startAutoAction: true,
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
            ignoreEmpty: true,
            autoResize: false,
          }, uiAditonalParams),
        },
      });
    };
    await registerCommand("DduRgLive", async () => {
      await dduWithPreview([{
        name: "rg",
        options: { matchers: [], volatile: true },
      }], { ignoreEmpty: false });
    });
    await registerCommand("DeinUpdate", async () => {
      await dduWithPreview([{ name: "dein_update" }]);
    });

    await registerCommand("LspDefinition", async () => {
      await dduWithPreview([{ name: "lsp_definition" }], {
        immediateAction: "open",
      });
    });
    await registerCommand("LspReferences", async () => {
      await dduWithPreview([{ name: "lsp_references" }]);
    });
    await registerCommand("LspDocumentSymbols", async () => {
      await dduWithPreview([{ name: "lsp_documentSymbol" }], {
        displayTree: true,
      });
    });
    await registerCommand("LspWorkspaceSymbol", async () => {
      await dduWithPreview([{
        name: "lsp_workspaceSymbol",
        options: { volatile: false },
      }], {
        ignoreEmpty: false,
      });
    });
    await registerCommand("LspIncomingCalls", async () => {
      await dduWithPreview([{
        name: "lsp_callHierarchy",
        params: { method: "callHierarchy/incomingCalls" },
      }], {
        displayTree: true,
      });
    });
    await registerCommand("LspOutgoingCalls", async () => {
      await dduWithPreview([{
        name: "lsp_callHierarchy",
        params: { method: "callHierarchy/outgoingCalls" },
      }], {
        displayTree: true,
      });
    });
    await registerCommand("LspCodeAction", async () => {
      await dduWithPreview([{ name: "lsp_codeAction" }]);
    });

    await registerCommand("DduRgPreview", async () => {
      const input = await helper.input(denops, { prompt: "Pattern: " });
      if (input == null) return;
      await dduWithPreview([{ name: "rg", params: { input: input } }]);
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
      const line = await op.lines.get(denops);
      const winHeight = line - 8;
      const winRow = (line - winHeight) / 2;
      await start({
        ui: "filer",
        name: "filer-" + await vars.t.get(denops, "ddu_filer_index", ""),
        resume: true,
        sync: true,
        uiParams: {
          filer: {
            split: "floating",
            winRow: winRow,
            winHeight: winHeight,
          },
        },
        sources: [{
          name: "file",
          options: {
            path: await vars.t.get(denops, "ddu_ui_filer_path", ""),
            // columns: ["icon_filename"],
            sorters: ["sorter_alpha"],
          },
        }],
        actionOptions: {
          narrow: {
            quit: false,
          },
        },
      });
    });
    await registerCommand("DduViewSpecSource", async (arg) => {
      const args = ensure(arg, is.String).split(" ");
      const histFile = args.find((v) => v.startsWith("file="))?.split("=")[1];
      const binPath = args.find((v) => v.startsWith("bin="))?.split("=")[1];
      const histlens = args.find((v) => v.startsWith("histlens="))?.split(
        "=",
      )[1];
      const targetAddr = args.find((v) => v.startsWith("addr="))?.split("=")[1];
      const shorten = args.find((v) =>
        v.startsWith("shorten=")
      )?.split("=")[1] ?? "0";
      const minN = args.find((v) => v.startsWith("minN="))?.split("=")[1] ??
        "0";
      const similar =
        args.find((v) => v.startsWith("similar="))?.split("=")[1] ?? "0";
      if (!histFile || !binPath || !histlens || !targetAddr) {
        return;
      }
      await dduWithPreview([{
        name: "spec_addrs",
        params: {
          binPath,
          histFile,
          histlens: histlens.split(",").map((v) => parseInt(v)),
          shorten: shorten === "1",
          targetAddr: parseInt(targetAddr),
          minN: parseInt(minN),
          similar: similar === "1",
        },
      }], {
        displayTree: true,
        maxHighlightItems: 1000,
      });
    });
    return Promise.resolve();
  }
}
