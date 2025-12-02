import { create } from 'zustand'
import { createClient } from '@/lib/supabase/client'
import toast from 'react-hot-toast'

export interface CovenTaskObjective {
  type: string
  target: number
  current?: number
  item?: string
  description?: string
}

export interface CovenTask {
  id: number
  coven_id: string
  name: string
  description: string
  objectives: CovenTaskObjective[]
  rewards: {
    coven_points?: number
    shared_crystals?: number
  }
  created_by: string
  created_at: string
  expires_at: string | null
  completed: boolean
  completed_at: string | null
}

export interface CovenTaskProgress {
  task_id: number
  player_id: string
  contribution: CovenTaskObjective[]
  contributed_at: string
}

export interface CovenTasksState {
  tasks: CovenTask[]
  taskProgress: Record<number, CovenTaskProgress[]> // task_id -> progress[]
  loading: boolean
  error: string | null
  setTasks: (tasks: CovenTask[]) => void
  setTaskProgress: (taskId: number, progress: CovenTaskProgress[]) => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  fetchTasks: (covenId: string) => Promise<void>
  fetchTaskProgress: (taskId: number) => Promise<void>
  createTask: (covenId: string, name: string, description: string, objectives: CovenTaskObjective[], rewards: any, expiresHours?: number) => Promise<void>
  contributeToTask: (taskId: number, objectiveType: string, increment?: number) => Promise<void>
  claimRewards: (taskId: number) => Promise<void>
  subscribeToTasks: (covenId: string) => () => void
}

export const useCovenTasksStore = create<CovenTasksState>((set, get) => ({
  tasks: [],
  taskProgress: {},
  loading: false,
  error: null,
  setTasks: (tasks) => set({ tasks, error: null }),
  setTaskProgress: (taskId, progress) => set((state) => ({
    taskProgress: { ...state.taskProgress, [taskId]: progress }
  })),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  fetchTasks: async (covenId: string) => {
    const { setTasks, setLoading, setError } = get()
    setLoading(true)
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('coven_tasks')
        .select('*')
        .eq('coven_id', covenId)
        .order('created_at', { ascending: false })
      if (error) throw error
      
      // Parse JSONB fields
      const tasks = (data || []).map(task => ({
        ...task,
        objectives: typeof task.objectives === 'string' ? JSON.parse(task.objectives) : task.objectives,
        rewards: typeof task.rewards === 'string' ? JSON.parse(task.rewards) : task.rewards
      }))
      
      setTasks(tasks)
      
      // Fetch progress for all tasks
      for (const task of tasks) {
        await get().fetchTaskProgress(task.id)
      }
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching coven tasks:', err)
    } finally {
      setLoading(false)
    }
  },
  fetchTaskProgress: async (taskId: number) => {
    const { setTaskProgress, setError } = get()
    setError(null)
    try {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('coven_task_progress')
        .select('*')
        .eq('task_id', taskId)
        .order('contributed_at', { ascending: false })
      if (error) throw error
      
      // Parse JSONB fields
      const progress = (data || []).map(p => ({
        ...p,
        contribution: typeof p.contribution === 'string' ? JSON.parse(p.contribution) : p.contribution
      }))
      
      setTaskProgress(taskId, progress)
    } catch (err: any) {
      setError(err.message)
      console.error('Error fetching task progress:', err)
    }
  },
  createTask: async (covenId: string, name: string, description: string, objectives: CovenTaskObjective[], rewards: any, expiresHours: number = 168) => {
    const { fetchTasks, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('create_coven_task', {
        p_coven_id: covenId,
        p_name: name,
        p_description: description,
        p_objectives: JSON.stringify(objectives),
        p_rewards: JSON.stringify(rewards),
        p_expires_hours: expiresHours
      })
      if (error) throw error
      toast.success('Coven task created!')
      await fetchTasks(covenId)
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to create task: ${err.message}`)
      console.error('Error creating task:', err)
      throw err
    }
  },
  contributeToTask: async (taskId: number, objectiveType: string, increment: number = 1) => {
    const { fetchTaskProgress, setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('contribute_to_task', {
        p_task_id: taskId,
        p_objective_type: objectiveType,
        p_increment: increment
      })
      if (error) throw error
      toast.success('Contribution recorded!')
      await fetchTaskProgress(taskId)
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to contribute: ${err.message}`)
      console.error('Error contributing to task:', err)
      throw err
    }
  },
  claimRewards: async (taskId: number) => {
    const { setError } = get()
    try {
      const supabase = createClient()
      const { error } = await supabase.rpc('claim_coven_task_rewards', {
        p_task_id: taskId
      })
      if (error) throw error
      toast.success('Rewards distributed to all members!')
    } catch (err: any) {
      setError(err.message)
      toast.error(`Failed to claim rewards: ${err.message}`)
      console.error('Error claiming rewards:', err)
      throw err
    }
  },
  subscribeToTasks: (covenId: string) => {
    const supabase = createClient()
    const channel = supabase.channel(`coven_tasks_${covenId}`)
    channel
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'coven_tasks', filter: `coven_id=eq.${covenId}` },
        () => {
          get().fetchTasks(covenId)
        }
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'coven_task_progress' },
        (payload) => {
          if (payload.new && 'task_id' in payload.new) {
            get().fetchTaskProgress((payload.new as any).task_id)
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },
}))

