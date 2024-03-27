import {
  BaseSource,
  Context,
  Item,
  SourceOptions,
} from "https://deno.land/x/ddu_vim@v3.10.3/types.ts";
import { Denops } from "https://deno.land/x/ddu_vim@v3.10.3/deps.ts";
import { ActionData } from "../@ddu-kinds/spec_history.ts";
import { basename } from "https://deno.land/std@0.220.1/path/mod.ts";

type Params = {
  histFile: string;
  binPath: string;
};

type GatherArgs = {
  denops: Denops;
  context: Context;
  sourceOptions: SourceOptions;
  sourceParams: Params;
};

function gather_positions(
  args: GatherArgs,
): ReadableStream<Item<ActionData>[]> {
  const addrs = (args.sourceOptions.path as string).split(" ");
  const command = new Deno.Command("addr2line", {
    args: ["-e", args.sourceParams.binPath, ...addrs],
  });
  const { code, stdout, stderr } = command.outputSync();
  if (code !== 0) {
    console.error(new TextDecoder().decode(stderr));
    return new ReadableStream({
      start(controller) {
        controller.close();
      },
    });
  }
  const lines = new TextDecoder().decode(stdout).trim().split("\n");
  const items: Item<ActionData>[] = lines.map((line) => {
    const [path, lineNr] = line.split(" ")[0].split(":");
    return {
      word: `${basename(path)}:${lineNr}`,
      action: {
        path,
        lineNr: Number(lineNr),
      },
    };
  });
  return new ReadableStream({
    start(controller) {
      controller.enqueue(items);
      controller.close();
    },
  });
}

function gather_path_histories(
  args: GatherArgs,
): ReadableStream<Item<ActionData>[]> {
  const histFile = args.sourceParams.histFile;
  const lines = Deno.readTextFileSync(histFile).trim().split("\n");
  const histories = lines.map((line) => line.trim().split(" "));
  const addr_index_map = new Map<string, number>();
  for (const addrs of histories) {
    for (const addr of addrs) {
      if (!addr_index_map.has(addr)) {
        addr_index_map.set(addr, addr_index_map.size);
      }
    }
  }
  const items: Item<ActionData>[] = histories.map((addrs) => {
    return {
      word: addrs.map((addr) => addr_index_map.get(addr)).join(" "),
      isTree: true,
      treePath: addrs.join(" "),
      action: {
        binPath: args.sourceParams.binPath,
      },
    };
  });
  return new ReadableStream({
    start(controller) {
      controller.enqueue(items);
      controller.close();
    },
  });
}

export class Source extends BaseSource<Params> {
  override kind = "spec_history";

  override gather(args: GatherArgs): ReadableStream<Item<ActionData>[]> {
    if (args.sourceOptions.path === "") {
      return gather_path_histories(args);
    } else {
      return gather_positions(args);
    }
  }

  override params(): Params {
    return { histFile: "", binPath: "" };
  }
}
