import { Denops } from "jsr:@denops/std@7.1.1";

export function main(denops: Denops) {
  denops.dispatcher = {
    echo(arg1: unknown): Promise<void> {
      console.log(arg1);
      return Promise.resolve();
    },
  };
}
