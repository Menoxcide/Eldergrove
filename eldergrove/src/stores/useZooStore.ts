import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

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
  animal1_produced_at: string | null
  animal2_produced_at: string | null
  breeding_started_at: string | null
  breeding_completes_at: string | null
  created_at: string
}

export interface ZooState {
  enclosures: ZooEnclosure[]
  animalTypes: AnimalType[]
  loading: boolean
  error: string | null
  setEnclosures: (enclosures: ZooEnclosure[]) => void
  setAnimalTypes: (types: AnimalType[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchEnclosures: () => Promise<void>
  fetchAnimalTypes: () => Promise<void>
  createEnclosure: (name: string) => Promise<void>
  addAnimalToEnclosure: (enclosureId: number, animalTypeId: number, slot: number) => Promise<void>
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
  setEnclosures: (enclosures) => set({ enclosures, error: null }),
  setAnimalTypes: (types) => set({ animalTypes: types, error: null }),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchEnclosures: async () => {
    const { setEnclosures, setLoading, setError } = get()
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
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching enclosures:', err)
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
      setError(err.message)
      console.error('Error fetching animal types:', err)
    } finally {
      setLoading(false)
    }
  },
  createEnclosure: async (name: string) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('create_enclosure', {
        p_enclosure_name: name
      })
      if (error) throw error
      toast.success('Enclosure created!')
      await fetchEnclosures()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to create enclosure: ${err.message}`)
      console.error('Error creating enclosure:', err)
      throw err
    }
  },
  addAnimalToEnclosure: async (enclosureId: number, animalTypeId: number, slot: number) => {
    const { fetchEnclosures, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('add_animal_to_enclosure', {
        p_enclosure_id: enclosureId,
        p_animal_type_id: animalTypeId,
        p_slot: slot
      })
      if (error) throw error
      toast.success('Animal added to enclosure!')
      await fetchEnclosures()
      // Refresh player profile to update crystals
      const { usePlayerStore } = await import('./usePlayerStore')
      await usePlayerStore.getState().fetchPlayerProfile()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to add animal: ${err.message}`)
      console.error('Error adding animal:', err)
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
      
      if (result.success) {
        toast.success(`Collected ${result.quantity} items!`)
        await fetchEnclosures()
        // Refresh inventory
        const { useInventoryStore } = await import('./useInventoryStore')
        useInventoryStore.getState().fetchInventory()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to collect production: ${err.message}`)
      console.error('Error collecting production:', err)
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
      toast.success('Breeding started!')
      await fetchEnclosures()
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to start breeding: ${err.message}`)
      console.error('Error starting breeding:', err)
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

      const result = data as { success: boolean; animal_name: string; animal_icon: string }
      
      if (result.success) {
        toast.success(`Bred ${result.animal_icon} ${result.animal_name}!`)
        await fetchEnclosures()
        // Refresh inventory
        const { useInventoryStore } = await import('./useInventoryStore')
        useInventoryStore.getState().fetchInventory()
      }
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to collect bred animal: ${err.message}`)
      console.error('Error collecting bred animal:', err)
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
          get().fetchEnclosures()
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

