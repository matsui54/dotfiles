import {
  BaseSource,
  Item,
} from "https://deno.land/x/ddu_vim@v0.7.0/types.ts#^";
import { Denops, fn } from "https://deno.land/x/ddu_vim@v0.4.0/deps.ts#^";
import { ActionData } from "../@ddu-kinds/highlight.ts";

type Params = {};

export class Source extends BaseSource<Params> {
  kind = "highlight";

  gather(args: {
    denops: Denops;
    sourceParams: Params;
  }): ReadableStream<Item<ActionData>[]> {
    return new ReadableStream({
      async start(controller) {
        const items: Item<ActionData>[] = [];

        try {
          const lines = (await fn.execute(
            args.denops,
            "highlight",
          ) as string).split("\n");
          lines.map((line) => {
            const m = line.match(/(\S*)\s+xxx/);
            if (!m || m.length < 2) return;
            items.push({
              word: line,
              highlights: [{
                name: "ddu-highlight-hl",
                "hl_group": m[1],
                col: line.indexOf("xxx") + 1,
                width: 3,
              }],
            });
          });
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
