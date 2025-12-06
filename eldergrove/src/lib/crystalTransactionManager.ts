/**
 * Crystal Transaction Manager
 *
 * Prevents race conditions in crystal operations by ensuring only one crystal-modifying
 * operation executes at a time. Operations are queued and executed sequentially.
 */

interface QueuedOperation {
  id: string;
  operation: () => Promise<void>;
  resolve: (value: void) => void;
  reject: (reason: unknown) => void;
  description: string;
}

class CrystalTransactionManager {
  private isProcessing = false;
  private operationQueue: QueuedOperation[] = [];
  private operationCounter = 0;

  /**
   * Executes a crystal operation, queuing it if another operation is in progress.
   * @param operation The async operation to execute
   * @param description Description for logging/debugging
   * @returns Promise that resolves when the operation completes
   */
  async executeCrystalOperation(
    operation: () => Promise<void>,
    description: string
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      const operationId = `crystal-op-${++this.operationCounter}`;
      const queuedOp: QueuedOperation = {
        id: operationId,
        operation,
        resolve,
        reject,
        description
      };

      this.operationQueue.push(queuedOp);
      this.processQueue();
    });
  }

  /**
   * Processes the operation queue sequentially
   */
  private async processQueue(): Promise<void> {
    if (this.isProcessing || this.operationQueue.length === 0) {
      return;
    }

    this.isProcessing = true;

    while (this.operationQueue.length > 0) {
      const currentOp = this.operationQueue.shift()!;

      try {
        await currentOp.operation();
        currentOp.resolve();
      } catch (error) {
        console.error(`[CrystalTransactionManager] Operation failed: ${currentOp.description} (ID: ${currentOp.id})`, error);
        currentOp.reject(error);
      }
    }

    this.isProcessing = false;
  }

  /**
   * Gets the current queue status for debugging
   */
  getQueueStatus(): { isProcessing: boolean; queueLength: number; queuedDescriptions: string[] } {
    return {
      isProcessing: this.isProcessing,
      queueLength: this.operationQueue.length,
      queuedDescriptions: this.operationQueue.map(op => op.description)
    };
  }

  /**
   * Clears the queue (useful for testing or emergency situations)
   */
  clearQueue(): void {
    console.warn('[CrystalTransactionManager] Clearing operation queue');
    this.operationQueue.forEach(op => {
      op.reject(new Error('Operation cancelled: queue cleared'));
    });
    this.operationQueue = [];
  }
}

// Export singleton instance
export const crystalTransactionManager = new CrystalTransactionManager();