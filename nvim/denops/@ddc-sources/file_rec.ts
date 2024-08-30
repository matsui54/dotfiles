import {
  BaseSource,
  Item,
} from "https://deno.land/x/ddc_vim@v6.0.0/types.ts";
import { vimoption2ts } from "https://deno.land/x/ddc_vim@v6.0.0/util.ts";
import {
  GatherArguments,
  GetCompletePositionArguments,
} from "https://deno.land/x/ddc_vim@v6.0.0/base/source.ts";
import * as fn from "https://deno.land/x/denops_std@v6.5.1/function/mod.ts";
import * as op from "https://deno.land/x/denops_std@v6.5.1/option/mod.ts";
import { relative, resolve } from "https://deno.land/std@0.224.0/path/mod.ts";

type Params = {
  cmd: string[];
  path: string;
};

async function getOutput(cwd: string, cmds: string[]): Promise<string[]> {
  try {
    const proc = Deno.run({
      cmd: cmds,
      stdout: "piped",
      stderr: "piped",
      cwd: cwd,
    });
    const [status, stdout, stderr] = await Promise.all([
      proc.status(),
      proc.output(),
      proc.stderrOutput(),
    ]);
    proc.close();

    if (!status.success) {
      console.error(new TextDecoder().decode(stderr));
      return [];
    }
    return (new TextDecoder().decode(stdout)).split("\n");
  } catch (e: unknown) {
    console.error(e);
    return [];
  }
}

export class Source extends BaseSource<Params> {
  async getCompletePosition({
    context,
    denops,
  }: GetCompletePositionArguments<Params>): Promise<number> {
    const fnamePattern = `[${
      vimoption2ts(await op.isfname.getGlobal(denops))
    }]*`;
    console.log(fnamePattern);
    const matchPos = context.input.search(
      new RegExp("(?:" + fnamePattern + ")$"),
    );
    console.log(matchPos);
    const completePos = matchPos ?? -1;
    return Promise.resolve(completePos);
  }

  async gather({
    denops,
    sourceParams,
  }: GatherArguments<Params>): Promise<Item[]> {
    let dir = await fn.expand(denops, sourceParams.path) as string;
    if (dir == "") {
      dir = await fn.getcwd(denops) as string;
    }

    console.log(dir);
    if (!sourceParams.cmd.length) {
      return [];
    }
    const paths = await getOutput(dir, sourceParams.cmd);
    const items: Item[] = [];
    paths.map((path) => {
      if (!path.length) return;
      const fullPath = resolve(dir, path);
      items.push({
        word: relative(dir, fullPath),
      });
    });
    return items;
  }

  params(): Params {
    return {
      cmd: [],
      path: "",
    };
  }
}
