// One serial lane per "channel + AI". Two messages sent back to back land on the
// same lane, so they can't fire two overlapping requests, come back out of
// order, or interleave writes. Different lanes run in parallel, which is what
// lets AI A and AI B think at the same time in the group chat.
export function createQueueSet() {
  /** @type {Map<string, Promise<void>>} */
  const lanes = new Map()

  return {
    /** Runs `task` after everything already queued on `key`. */
    run(key, task) {
      const prev = lanes.get(key) ?? Promise.resolve()
      // Run on both settle paths so one failure doesn't wedge the lane.
      const result = prev.then(task, task)
      const tail = result.then(
        () => {},
        () => {},
      )
      lanes.set(key, tail)
      tail.then(() => {
        // Only the lane's current tail may retire the key; a later enqueue wins.
        if (lanes.get(key) === tail) lanes.delete(key)
      })
      return result
    },

    get depth() {
      return lanes.size
    },

    /** Waits for every lane to finish. Used by tests and graceful shutdown. */
    async drain() {
      while (lanes.size) await Promise.allSettled([...lanes.values()])
    },
  }
}
