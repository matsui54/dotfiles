import {
  BaseSource,
  Item,
} from "https://deno.land/x/ddu_vim@v5.0.0/types.ts";
import { Denops, fn } from "https://deno.land/x/ddu_vim@v5.0.0/deps.ts";
import { ActionData } from "https://deno.land/x/ddu_kind_file@v0.8.0/file.ts";

type Params = {};

type VsnipItem = {
  body: string | string[];
  description: string;
  label: string;
  prefix: string[];
  prefix_alias: string[];
};

export class Source extends BaseSource<Params> {
  kind = "file";

  gather(args: {
    denops: Denops;
    sourceParams: Params;
  }): ReadableStream<Item<ActionData>[]> {
    return new ReadableStream({
      async start(controller) {
        const items: Item<ActionData>[] = [];

        try {
          const sources = await args.denops.eval(
            "vsnip#source#find(bufnr())",
          ) as VsnipItem[][];
          for (const source of sources) {
            for (const snip of source) {
              const label = snip.label;
              const prefix = snip.prefix.join(" ").padEnd(20, " ");
              items.push({
                word: `${prefix}   ${label}   ${snip.description}`,
                highlights: [{
                  name: "ddu-vsnip-hl",
                  "hl_group": "Label",
                  col: 1,
                  width: prefix.length,
                }, {
                  name: "ddu-vsnip-hl",
                  "hl_group": "Number",
                  col: prefix.length + 4,
                  width: label.length,
                }],
              });
            }
          }
          controller.enqueue(items);
        } catch (e) {
          console.error(e);
        }
        controller.close();
      },
    });
  }

  params(): Params {
    return {};
  }
}
