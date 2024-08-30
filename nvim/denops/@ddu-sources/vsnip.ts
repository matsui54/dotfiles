import { type Item } from "jsr:@shougo/ddu-vim@6.1.0/types";
import { BaseSource } from "jsr:@shougo/ddu-vim@6.1.0/source";
import type { Denops } from "jsr:@denops/std@~7.1.0";
import { ActionData } from "jsr:@shougo/ddu-kind-file@0.9.0";

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
