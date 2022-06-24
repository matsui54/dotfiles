import { Denops } from "https://deno.land/x/denops_std@v3.3.2/mod.ts";

export function main(denops: Denops) {
  denops.dispatcher = {
    echo(arg1: unknown): Promise<void> {
      console.log(arg1);
      return Promise.resolve();
    },
  };
}
