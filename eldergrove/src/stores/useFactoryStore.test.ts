import { useFactoryStore } from './useFactoryStore'
import { usePlayerStore } from './usePlayerStore'
import { createClient } from '@/lib/supabase/client'
import { crystalTransactionManager } from '@/lib/crystalTransactionManager'

// Mock dependencies
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}))
jest.mock('./usePlayerStore', () => ({
  usePlayerStore: {
    getState: jest.fn(),
    setState: jest.fn(),
  },
}))
jest.mock('@/stores/useGameMessageStore', () => ({
  useGameMessageStore: {
    getState: jest.fn(() => ({
      addMessage: jest.fn(),
    })),
  },
}))
jest.mock('@/lib/audio')
jest.mock('@/lib/crystalTransactionManager')

const mockCreateClient = createClient as jest.MockedFunction<typeof createClient>
const mockUsePlayerStore = usePlayerStore as any
const mockCrystalTransactionManager = crystalTransactionManager as jest.Mocked<typeof crystalTransactionManager>

describe('useFactoryStore - Crystal Economy', () => {
  let mockSupabaseClient: any
  let mockPlayerStore: any

  beforeEach(() => {
    // Reset all mocks
    jest.clearAllMocks()

    // Setup mock Supabase client
    mockSupabaseClient = {
      rpc: jest.fn(),
    }
    mockCreateClient.mockReturnValue(mockSupabaseClient)

    // Setup mock player store
    mockPlayerStore = {
      crystals: 1000,
      setCrystals: jest.fn(),
      fetchPlayerProfile: jest.fn(),
    }
    mockUsePlayerStore.getState.mockReturnValue(mockPlayerStore)

    // Mock the crystal transaction manager to execute operations synchronously
    mockCrystalTransactionManager.executeCrystalOperation = jest.fn(async (operation: () => Promise<void>, description: string) => { await operation(); }) as any

    // Reset store state
    useFactoryStore.getState().setError(null)
  })

  describe('collectFactory', () => {
    it('should use new_crystal_balance from RPC response for successful collection', async () => {
      const mockResponse = {
        success: true,
        output: { bread: 5 },
        xp_gained: 10,
        new_crystal_balance: 1050,
        crystals_awarded: 50,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await useFactoryStore.getState().collectFactory(1)

      expect(mockPlayerStore.setCrystals).toHaveBeenCalledWith(1050)
      expect(mockPlayerStore.setCrystals).toHaveBeenCalledTimes(1)
    })

    it('should validate new_crystal_balance is not negative', async () => {
      const mockResponse = {
        success: true,
        output: { bread: 5 },
        xp_gained: 10,
        new_crystal_balance: -50, // Invalid negative balance
        crystals_awarded: 50,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await expect(useFactoryStore.getState().collectFactory(1)).rejects.toThrow(
        'Collection would result in negative crystal balance'
      )

      // Should restore old crystal balance on validation failure
      expect(mockPlayerStore.setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should preserve crystal state on RPC error', async () => {
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: 'Database error' }
      })

      await expect(useFactoryStore.getState().collectFactory(1)).rejects.toThrow()

      // Should restore old crystal balance
      expect(mockPlayerStore.setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should preserve crystal state on network failure', async () => {
      mockSupabaseClient.rpc.mockRejectedValue(new Error('Network error'))

      await expect(useFactoryStore.getState().collectFactory(1)).rejects.toThrow()

      // Should restore old crystal balance
      expect(mockPlayerStore.setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should not call fetchPlayerProfile after successful collection', async () => {
      const mockResponse = {
        success: true,
        output: { bread: 5 },
        xp_gained: 10,
        new_crystal_balance: 1050,
        crystals_awarded: 50,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await useFactoryStore.getState().collectFactory(1)

      expect(mockPlayerStore.fetchPlayerProfile).not.toHaveBeenCalled()
    })
  })

  describe('purchaseFactorySlot', () => {
    it('should preserve crystal state on purchase failure', async () => {
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: 'Insufficient funds' }
      })

      await expect(useFactoryStore.getState().purchaseFactorySlot()).rejects.toThrow()

      // Should restore old crystal balance
      expect(mockPlayerStore.setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should call fetchPlayerProfile after successful purchase', async () => {
      const mockResponse = {
        success: true,
        cost_paid: 500,
        new_max_slots: 3,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await useFactoryStore.getState().purchaseFactorySlot()

      expect(mockPlayerStore.fetchPlayerProfile).toHaveBeenCalledTimes(1)
    })
  })
})