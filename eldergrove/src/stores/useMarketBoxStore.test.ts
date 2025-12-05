import { useMarketBoxStore } from './useMarketBoxStore'
import { usePlayerStore } from './usePlayerStore'
import { createClient } from '@/lib/supabase/client'

// Mock dependencies
jest.mock('@/lib/supabase/client')
jest.mock('./usePlayerStore')
jest.mock('@/stores/useGameMessageStore')
jest.mock('./useInventoryStore')

const mockCreateClient = createClient as jest.MockedFunction<typeof createClient>
const mockUsePlayerStore = usePlayerStore as jest.MockedFunction<typeof usePlayerStore>

describe('useMarketBoxStore - Crystal Economy', () => {
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
      getState: jest.fn(() => ({
        crystals: 1000,
        setCrystals: jest.fn(),
        fetchPlayerProfile: jest.fn(),
      })),
    }
    mockUsePlayerStore.mockReturnValue(mockPlayerStore)

    // Setup mock market listings
    useMarketBoxStore.setState({
      listings: [
        {
          id: 1,
          seller_id: 'seller-1',
          item_id: 1,
          quantity: 10,
          price_crystals: 500,
          created_at: '2024-01-01T00:00:00Z',
          expires_at: '2024-01-02T00:00:00Z',
          purchased_at: null,
          buyer_id: null,
        }
      ],
      error: null,
    })
  })

  describe('purchaseListing', () => {
    it('should use new_crystal_balance from RPC response for successful purchase', async () => {
      const mockResponse = {
        success: true,
        item_id: 1,
        quantity: 5,
        cost: 500,
        new_crystal_balance: 500,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await useMarketBoxStore.getState().purchaseListing(1)

      expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(500)
      expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledTimes(1)
    })

    it('should validate sufficient crystals before purchase', async () => {
      // Set player crystals lower than listing price
      mockPlayerStore.getState = jest.fn(() => ({
        crystals: 300, // Less than 500 needed
        setCrystals: jest.fn(),
        fetchPlayerProfile: jest.fn(),
      }))

      await expect(useMarketBoxStore.getState().purchaseListing(1)).rejects.toThrow(
        'Insufficient crystals. You have 300 but need 500 crystals.'
      )

      // Should not call RPC if insufficient crystals
      expect(mockSupabaseClient.rpc).not.toHaveBeenCalled()
    })

    it('should validate new_crystal_balance is not negative', async () => {
      const mockResponse = {
        success: true,
        item_id: 1,
        quantity: 5,
        cost: 500,
        new_crystal_balance: -100, // Invalid negative balance
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await expect(useMarketBoxStore.getState().purchaseListing(1)).rejects.toThrow(
        'Transaction would result in negative crystal balance'
      )

      // Should restore old crystal balance on validation failure
      expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should preserve crystal state on RPC error', async () => {
      mockSupabaseClient.rpc.mockResolvedValue({
        data: null,
        error: { message: 'Database error' }
      })

      await expect(useMarketBoxStore.getState().purchaseListing(1)).rejects.toThrow()

      // Should restore old crystal balance
      expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should preserve crystal state on network failure', async () => {
      mockSupabaseClient.rpc.mockRejectedValue(new Error('Network error'))

      await expect(useMarketBoxStore.getState().purchaseListing(1)).rejects.toThrow()

      // Should restore old crystal balance
      expect(mockPlayerStore.getState().setCrystals).toHaveBeenCalledWith(1000)
    })

    it('should not call fetchPlayerProfile after successful purchase', async () => {
      const mockResponse = {
        success: true,
        item_id: 1,
        quantity: 5,
        cost: 500,
        new_crystal_balance: 500,
      }

      mockSupabaseClient.rpc.mockResolvedValue({ data: mockResponse, error: null })

      await useMarketBoxStore.getState().purchaseListing(1)

      expect(mockPlayerStore.getState().fetchPlayerProfile).not.toHaveBeenCalled()
    })

    it('should throw error when listing not found', async () => {
      await expect(useMarketBoxStore.getState().purchaseListing(999)).rejects.toThrow(
        'Listing not found'
      )

      // Should not call RPC if listing not found
      expect(mockSupabaseClient.rpc).not.toHaveBeenCalled()
    })
  })
})