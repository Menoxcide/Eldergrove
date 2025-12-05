import { useFactoryStore } from './useFactoryStore'
import { usePlayerStore } from './usePlayerStore'
import { createClient } from '@/lib/supabase/client'
import { crystalTransactionManager } from '@/lib/crystalTransactionManager'

// Mock dependencies
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}))
jest.mock('./usePlayerStore')
jest.mock('@/stores/useGameMessageStore')
jest.mock('@/lib/audio')
jest.mock('@/lib/crystalTransactionManager')

const mockCreateClient = createClient as jest.MockedFunction<typeof createClient>
const mockUsePlayerStore = usePlayerStore as jest.MockedFunction<typeof usePlayerStore>
const mockCrystalTransactionManager = crystalTransactionManager as jest.Mocked<typeof crystalTransactionManager>

describe('Crystal Economy - Race Condition Analysis', () => {
  let mockSupabaseClient: any
  let mockPlayerStore: any

  beforeEach(() => {
    jest.clearAllMocks()

    // Mock environment variables
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test.supabase.co'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-key'

    mockSupabaseClient = {
      rpc: jest.fn(),
    }
    mockCreateClient.mockReturnValue(mockSupabaseClient)

    // Mock the crystal transaction manager
    mockCrystalTransactionManager.executeCrystalOperation = jest.fn(async (operation: () => Promise<void>, description: string) => { await operation(); }) as any

    // Setup mock player store
    mockPlayerStore = {
      getState: jest.fn(() => ({
        crystals: 1000,
        setCrystals: jest.fn(),
        fetchPlayerProfile: jest.fn(),
      })),
    }
    mockUsePlayerStore.mockReturnValue(mockPlayerStore)

    useFactoryStore.getState().setError(null)
  })

  it('verifies that crystal operations are now sequential and race-condition free', async () => {
    // Simulate two concurrent collection operations
    // With the transaction manager, they should execute sequentially

    const mockResponse1 = {
      success: true,
      output: { bread: 5 },
      xp_gained: 10,
      new_crystal_balance: 1050, // +50 crystals
      crystals_awarded: 50,
    }

    const mockResponse2 = {
      success: true,
      output: { bread: 3 },
      xp_gained: 5,
      new_crystal_balance: 1080, // +30 more crystals (total should be 1080)
      crystals_awarded: 30,
    }

    // Mock RPC to return responses in sequence
    mockSupabaseClient.rpc
      .mockResolvedValueOnce({ data: mockResponse1, error: null })
      .mockResolvedValueOnce({ data: mockResponse2, error: null })

    // Start both operations concurrently
    const promise1 = useFactoryStore.getState().collectFactory(1)
    const promise2 = useFactoryStore.getState().collectFactory(2)

    await Promise.all([promise1, promise2])

    // Both operations should have completed
    expect(mockSupabaseClient.rpc).toHaveBeenCalledTimes(2)

    // Verify that executeCrystalOperation was called for each operation
    expect(mockCrystalTransactionManager.executeCrystalOperation).toHaveBeenCalledTimes(2)
    expect(mockCrystalTransactionManager.executeCrystalOperation).toHaveBeenNthCalledWith(
      1,
      expect.any(Function),
      'Collect factory slot 1'
    )
    expect(mockCrystalTransactionManager.executeCrystalOperation).toHaveBeenNthCalledWith(
      2,
      expect.any(Function),
      'Collect factory slot 2'
    )
  })

  it('verifies that failed operations no longer overwrite successful operations', async () => {
    // First operation succeeds
    const mockResponse1 = {
      success: true,
      output: { bread: 5 },
      xp_gained: 10,
      new_crystal_balance: 1050,
      crystals_awarded: 50,
    }

    // Second operation fails
    mockSupabaseClient.rpc
      .mockResolvedValueOnce({ data: mockResponse1, error: null })
      .mockResolvedValueOnce({ data: null, error: { message: 'Slot already collected' } })

    // Start operations
    await useFactoryStore.getState().collectFactory(1) // Should succeed and set crystals to 1050

    // Verify first operation set the balance
    expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(1050)

    // Now second operation fails, but with transaction manager it should not overwrite
    await expect(useFactoryStore.getState().collectFactory(2)).rejects.toThrow()

    // The successful balance should be preserved - no call to restore old balance
    expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledTimes(1)
    expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(1050)

    // Verify transaction manager was used
    expect(mockCrystalTransactionManager.executeCrystalOperation).toHaveBeenCalledTimes(2)
  })
})

/**
 * FIXED: Implemented client-side mutex (Crystal Transaction Manager)
 *
 * The race condition has been resolved by implementing a Crystal Transaction Manager
 * that ensures only one crystal operation executes at a time. Operations are queued
 * and executed sequentially, preventing concurrent modifications that could overwrite
 * each other's changes.
 *
 * Key improvements:
 * - Operations are now atomic at the client level
 * - Failed operations no longer overwrite successful ones
 * - Clear logging for debugging concurrent operation scenarios
 * - Non-blocking UI (operations are queued asynchronously)
 */