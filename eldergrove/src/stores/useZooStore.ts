import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import { handleError } from '@/hooks/useErrorHandler'
import { getItemNameWithLevel, getItemIconWithAnimal } from '@/lib/itemUtils'

export interface AnimalType {
  id: number
  name: string
  rarity: 'common' | 'rare' | 'legendary'
  base_cost_crystals: number
  produces_item_id: number | null
  produces_quantity: number
  produces_interval_minutes: number
  breeding_time_minutes: number
  icon: string
  description: string | null
}

export interface ZooEnclosure {
  id: number
  player_id: string
  enclosure_name: string
  animal1_id: number | null
  animal2_id: number | null
  animal1_level: number | null
  animal2_level: number | null
  animal1_produced_at: string | null
  animal2_produced_at: string | null
  breeding_started_at: string | null
  breeding_completes_at: string | null
  created_at: string
}

export interface EnclosureCostInfo {
  current_count: number
  max_enclosures: number
  can_create_free: boolean
  next_cost: number
  at_limit: boolean
}

export interface ZooState {
  enclosures: ZooEnclosure[]
  animalTypes: AnimalType[]
  loading: boolean
  error: string | null
  enclosureCostInfo: EnclosureCostInfo | null
  setEnclosures: (enclosures: ZooEnclosure[]) => void
  setAnimalTypes: (types: AnimalType[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchEnclosures: () => Promise<void>
  fetchAnimalTypes: () => Promise<void>
  getEnclosureCostInfo: () => Promise<void>
  createEnclosure: (name: string) => Promise<void>
  addAnimalToEnclosure: (enclosureId: number, animalTypeId: number, slot: number) => Promise<void>
  removeAnimalFromEnclosure: (enclosureId: number, slot: number) => Promise<void>
  collectProduction: (enclosureId: number, slot: number) => Promise<void>
  startBreeding: (enclosureId: number) => Promise<void>
  collectBredAnimal: (enclosureId: number) => Promise<void>
  subscribeToZoo: () => () => void
}

export const useZooStore = create<ZooState>((set, get) => ({
  enclosures: [],
  animalTypes: [],
  loading: false,
  error: null,
  enclosureCostInfo: null,
  setEnclosures: (enclosures) => set({ enclosures, error: null }),
  setAnimalTypes: (types) => set({ animalTypes: types, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  getEnclosureCostInfo: async () => {
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('get_next_enclosure_cost')
      if (error) throw error
      set({ enclosureCostInfo: data as EnclosureCostInfo })
    } catch (err: any) {
      console.error('Error fetching enclosure cost info:', err)
    }
  },
  fetchEnclosures: async () => {
    const { setEnclosures, setLoading, setError, getEnclosureCostInfo } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        throw new Error('No authenticated user')
      }
      const { data, error } = await supabase
        .from('zoo_enclosures')
        .select('*')
        .eq('player_id', user.id)
        .order('created_at', { ascending: true })
      if (error) throw error
      setEnclosures(data || [])
      // Also fetch cost info
      await getEnclosureCostInfo()
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch enclosures'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  fetchAnimalTypes: async () => {
    const { setAnimalTypes, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('animal_types')
        .select('*')
        .order('rarity', { ascending: true })
        .order('base_cost_crystals', { ascending: true })
      if (error) throw error
      setAnimalTypes(data || [])
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to fetch animal types'
      setError(errorMessage)
      handleError(err, errorMessage)
    } finally {
      setLoading(false)
    }
  },
  createEnclosure: async (name: string) => {
    const { fetchEnclosures, getEnclosureCostInfo, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('create_enclosure', {
        p_enclosure_name: name
      })
      if (error) throw error
      
      const result = data as { success: boolean; cost_paid: number; new_max_enclosures: number; new_crystal_balance?: number }
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      if (result.cost_paid > 0) {
        useGameMessageStore.getState().addMessage(
          'success',
          `Enclosure created! Paid ${result.cost_paid} crystals for slot expansion.`
        )
      } else {
        useGameMessageStore.getState().addMessage('success', 'Enclosure created!')
      }
      
      // Update crystal balance from returned value
      if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
        const { usePlayerStore } = await import('./usePlayerStore')
        usePlayerStore.getState().setCrystals(result.new_crystal_balance)
      }
      
      await fetchEnclosures()
      await getEnclosureCostInfo()
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while creating the enclosure'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  addAnimalToEnclosure: async (enclosureId: number, animalTypeId: number, slot: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('add_animal_to_enclosure', {
        p_enclosure_id: enclosureId,
        p_animal_type_id: animalTypeId,
        p_slot: slot
      })
      if (error) throw error
      
      const result = data as { success: boolean; new_crystal_balance?: number }
      
      // Update crystal balance from returned value
      if (result.new_crystal_balance !== null && result.new_crystal_balance !== undefined) {
        const { usePlayerStore } = await import('./usePlayerStore')
        usePlayerStore.getState().setCrystals(result.new_crystal_balance)
      }
      
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Animal added to enclosure!')
      await fetchEnclosures()
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while adding the animal'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  removeAnimalFromEnclosure: async (enclosureId: number, slot: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_animal_from_enclosure', {
        p_enclosure_id: enclosureId,
        p_slot: slot
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Animal removed from enclosure and returned to inventory!')
      await fetchEnclosures()
      // Refresh inventory to show the returned animal
      const { useInventoryStore } = await import('./useInventoryStore')
      await useInventoryStore.getState().fetchInventory()
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while removing the animal'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  collectProduction: async (enclosureId: number, slot: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('collect_animal_production', {
        p_enclosure_id: enclosureId,
        p_slot: slot
      })
      if (error) throw error

      const result = data as { success: boolean; item_id: number; quantity: number }
      
      if (result && result.success) {
        await fetchEnclosures()
        // Refresh inventory to show collected items
        const { useInventoryStore } = await import('./useInventoryStore')
        await useInventoryStore.getState().fetchInventory()
        
        // Show visual feedback
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        useGameMessageStore.getState().addMessage(
          'collection',
          'Collection Complete!',
          {
            itemIds: { [result.item_id]: result.quantity },
          }
        )
      } else {
        throw new Error('Failed to collect production - operation did not complete successfully')
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while collecting production'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  startBreeding: async (enclosureId: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('start_breeding', {
        p_enclosure_id: enclosureId
      })
      if (error) throw error
      const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
      useGameMessageStore.getState().addMessage('success', 'Breeding started!')
      await fetchEnclosures()
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while starting breeding'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  collectBredAnimal: async (enclosureId: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { data, error } = await supabase.rpc('collect_bred_animal', {
        p_enclosure_id: enclosureId
      })
      if (error) throw error

      const result = data as { success: boolean; animal_name: string; animal_icon: string; animal_level?: number; item_id?: number }
      
      if (result && result.success) {
        await fetchEnclosures()
        // Refresh inventory to show bred animal
        const { useInventoryStore } = await import('./useInventoryStore')
        await useInventoryStore.getState().fetchInventory()
        
        // Show visual feedback
        const { useGameMessageStore } = await import('@/stores/useGameMessageStore')
        if (result.item_id) {
          // Use proper item name with level
          const itemName = getItemNameWithLevel(result.item_id)
          const itemIcon = getItemIconWithAnimal(result.item_id)
          useGameMessageStore.getState().addMessage(
            'collection',
            'Collection Complete!',
            {
              itemIds: { [result.item_id]: 1 },
            }
          )
          // Also show a success message with the proper name
          useGameMessageStore.getState().addMessage(
            'success',
            `Bred ${itemIcon} ${itemName}!`
          )
        } else {
          // Fallback: show simple message
          const levelText = result.animal_level !== undefined ? ` +${result.animal_level}` : ''
          useGameMessageStore.getState().addMessage(
            'success',
            `Bred ${result.animal_icon} ${result.animal_name}${levelText}!`
          )
        }
      } else {
        throw new Error('Failed to collect bred animal - operation did not complete successfully')
      }
    } catch (err: any) {
      const errorMessage = err?.message || 'An unexpected error occurred while collecting the bred animal'
      setError(errorMessage)
      handleError(err, errorMessage)
      throw err
    }
  },
  subscribeToZoo: () => {
    const supabase = createClient()
    const channel = supabase.channel('zoo')
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'zoo_enclosures' },
        () => {
          get().fetchEnclosures().catch((err) => {
            console.error('Error in subscription callback:', err)
          })
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Subscribed to zoo updates')
        } else if (status === 'CHANNEL_ERROR') {
          const { setError } = get()
          setError('Failed to subscribe to real-time updates')
          console.error('Subscription error for zoo')
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

