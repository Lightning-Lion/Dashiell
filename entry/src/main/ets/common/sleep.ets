/**
 * A JavaScript function that mimics Swift's await Task.sleep(for:.seconds(xxx))
 *
 * @param {number} seconds - The number of seconds to sleep
 * @returns {Promise<void>} - A promise that resolves after the specified time
 *
 * Usage example:
 *
 * async function example() {
 *   console.debug("Starting...");
 *   await sleep.seconds(2);  // Sleep for 2 seconds
 *   console.debug("After 2 seconds");
 * }
 */

export class Task {
  /**
   * Sleep for the specified number of seconds
   * @param {number} seconds - The number of seconds to sleep
   * @returns {Promise<void>}
   */
  static sleep(seconds:number) {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, seconds * 1000)
    });
  }
};

// Example usage:
async function demo() {
  console.debug("Starting demo...");

  console.debug("Sleeping for 2 seconds...");
  await Task.sleep(2);
  console.debug("Woke up after 2 seconds");
  console.debug("Demo completed");
}