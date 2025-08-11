import {
  BaseConfig,
  type ConfigArguments,
} from "jsr:@shougo/ddc-vim@7.0.0/config";

export class Config extends BaseConfig {
  override async config(args: ConfigArguments): Promise<void> {
    const hasNvim = args.denops.meta.host === "nvim";

    args.contextBuilder.patchGlobal({
      ui: "pum",
      sources: ["lsp", "buffer", "around", "vsnip", "dictionary"],
      cmdlineSources: {
        ":": ["cmdline", "buffer"],
        "@": ["buffer", "input"],
        "=": ["input"],
        "/": [],
      },
      postFilters: ["postfilter_score"],
      autoCompleteEvents: [
        "InsertEnter",
        "TextChangedI",
        "TextChangedP",
        "CmdlineEnter",
        "CmdlineChanged",
      ],
      specialBufferCompletion: true,
      sourceOptions: {
        _: {
          matchers: ["matcher_fuzzy"],
          sorters: ["sorter_fuzzy"],
          converters: ["converter_remove_overlap", "converter_truncate"],
          ignoreCase: true,
        },
        around: { "mark": "[A]" },
        cmdline: {
          mark: "[cmd]",
          forceCompletionPattern: "\\s|/|-",
          minAutoCompleteLength: 1,
        },
        "cmdline-history": {
          matchers: ["matcher_head"],
          sorters: [],
          mark: "[hist]",
          minAutoCompleteLength: 1,
          maxItems: 3,
        },
        dictionary: {
          matchers: ["matcher_editdistance"],
          sorters: [],
          converters: ["converter_fuzzy"],
          maxItems: 6,
          mark: "[D]",
          minAutoCompleteLength: 3,
        },
        necovim: { "mark": "[neco]", "maxItems": 6 },
        lsp: {
          mark: "[lsp]",
          dup: "keep",
          minAutoCompleteLength: 10000,
          converters: ["converter_kind_labels"],
          sorters: ["sorter_lsp-kind"],
        },
        "vim-lsp": {
          mark: "[lsp]",
          dup: "keep",
          forceCompletionPattern: "\\.|:\\s*|->",
          minAutoCompleteLength: 1,
        },
        buffer: { "mark": "[B]", "maxItems": 10 },
        file: {
          mark: "[F]",
          isVolatile: true,
          forceCompletionPattern: "\\S\/\\S*",
          minAutoCompleteLength: 1,
        },
        "latex-symbols": {
          mark: "[latex]",
          forceCompletionPattern: "\\",
        },
        file_rec: { "mark": "[P]", "minAutoCompleteLength": 1 },
        // emoji: {
        //   mark: "[emoji]",
        //   dup: "keep",
        //   matcherKey: "kind",
        //   minAutoCompleteLength: 1,
        // },
        vsnip: { "mark": "[V]", "dup": "keep" },
        // skkeleton: {
        //   mark: "[skk]",
        //   matchers: [],
        //   sorters: [],
        //   isVolatile: true,
        //   minAutoCompleteLength: 2,
        // },
        zsh: {
          mark: "[Z]",
          forceCompletionPattern: "^!.*",
          minAutoCompleteLength: 10000,
        },
      },
      sourceParams: {
        around: { "maxSize": 500 },
        file_rec: { "cmd": ["fd", "--max-depth", "5"] },
        buffer: {
          forceCollect: true,
          fromAltBuf: true,
          bufNameStyle: "basename",
        },
        dictionary: { "smartCase": true, "showMenu": false },
        lsp: {
          enableResolveItem: true,
          enableAdditionalTextEdit: true,
          snippetEngine: await args.denops.eval(
            "denops#callback#register({ body -> vsnip#anonymous(body) })",
          ),
        },
      },
      filterParams: {
        converter_truncate: {
          maxAbbrWidth: 60,
          maxInfo: 500,
          maxMenuWidth: 0,
          ellipsis: "...",
        },
        converter_fuzzy: { "hlGroup": "Title" },
        postfilter_score: {
          excludeSources: ["dictionary", "skkeleton", "emoji"],
        },
        converter_kind_labels: {
          kindLabels: {
            Text: "",
            Method: "",
            Function: "",
            Constructor: "",
            Field: "",
            Variable: "",
            Class: "",
            Interface: "",
            Module: "",
            Property: "",
            Unit: "",
            Value: "",
            Enum: "",
            Keyword: "",
            Snippet: "",
            Color: "",
            File: "",
            Reference: "",
            Folder: "",
            EnumMember: "",
            Constant: "",
            Struct: "",
            Event: "",
            Operator: "",
            TypeParameter: "",
          },
          kindHlGroups: {
            Method: "Function",
            Function: "Function",
            Constructor: "Function",
            Field: "Identifier",
            Variable: "Identifier",
            Class: "Structure",
            Interface: "Structure",
          },
        },
      },
    });

    for (
      const ft of [
        "denite-filter",
        "ddu-ff-filter",
        "TelescopePrompt",
      ]
    ) {
      args.contextBuilder.patchFiletype(ft, {
        specialBufferCompletion: false,
      });
    }

    args.contextBuilder.patchFiletype("toml", {
      sources: [
        "necovim",
        "buffer",
        "around",
        "vsnip",
        "file",
        "dictionary",
      ],
    });
    args.contextBuilder.patchFiletype("zsh", {
      sources: [
        "zsh",
        "buffer",
        "around",
        "vsnip",
        "file",
        "dictionary",
      ],
    });
    args.contextBuilder.patchFiletype("tex", {
      sourceOptions: {
        vsnip: {
          forceCompletionPattern: "@",
          keywordPattern: "[a-zA-Z0-9_@]*",
        },
      },
    });
  }
}
