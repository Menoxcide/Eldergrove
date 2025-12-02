'use client';

import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { useZooStore, type ZooEnclosure, type AnimalType } from '@/stores/useZooStore';
import { usePlayerStore } from '@/stores/usePlayerStore';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { getItemIcon, getItemName } from '@/lib/itemUtils';

interface EnclosureCardProps {
  enclosure: ZooEnclosure;
  animalTypes: AnimalType[];
  onAddAnimal: (enclosureId: number, animalTypeId: number, slot: number) => void;
  onCollectProduction: (enclosureId: number, slot: number) => void;
  onStartBreeding: (enclosureId: number) => void;
  onCollectBred: (enclosureId: number) => void;
}

const EnclosureCard: React.FC<EnclosureCardProps> = ({
  enclosure,
  animalTypes,
  onAddAnimal,
  onCollectProduction,
  onStartBreeding,
  onCollectBred
}) => {
  const animal1 = enclosure.animal1_id ? animalTypes.find(a => a.id === enclosure.animal1_id) : null;
  const animal2 = enclosure.animal2_id ? animalTypes.find(a => a.id === enclosure.animal2_id) : null;

  const canCollect1 = animal1 && enclosure.animal1_produced_at && 
    new Date(enclosure.animal1_produced_at).getTime() + (animal1.produces_interval_minutes * 60 * 1000) <= Date.now();
  const canCollect2 = animal2 && enclosure.animal2_produced_at && 
    new Date(enclosure.animal2_produced_at).getTime() + (animal2.produces_interval_minutes * 60 * 1000) <= Date.now();
  const canBreed = animal1 && animal2 && !enclosure.breeding_started_at;
  const breedingComplete = enclosure.breeding_completes_at && 
    new Date(enclosure.breeding_completes_at).getTime() <= Date.now();

  const formatTimeLeft = (completesAt: string): string => {
    const now = Date.now();
    const completes = new Date(completesAt).getTime();
    const diff = completes - now;
    if (diff <= 0) return 'Ready!';
    const minutes = Math.floor(diff / (1000 * 60));
    return `${minutes}m`;
  };

  return (
    <div className="bg-gradient-to-br from-green-900 to-emerald-900 rounded-2xl p-6 border-2 border-green-500/30 shadow-lg">
      <h3 className="text-xl font-bold text-white mb-4">{enclosure.enclosure_name}</h3>
      
      <div className="grid grid-cols-2 gap-4 mb-4">
        {/* Slot 1 */}
        <div className="bg-white/10 rounded-lg p-4">
          {animal1 ? (
            <>
              <div className="text-center mb-2">
                <span className="text-4xl">{animal1.icon}</span>
                <div className="text-white font-semibold text-sm">{animal1.name}</div>
                <div className="text-slate-300 text-xs capitalize">{animal1.rarity}</div>
              </div>
              {canCollect1 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 1)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal1.produces_item_id || 0)} {animal1.produces_quantity}
                </button>
              )}
              {!canCollect1 && animal1 && (
                <div className="text-slate-400 text-xs text-center">Producing...</div>
              )}
            </>
          ) : (
            <button
              onClick={() => {
                // Show animal selection modal
                const modal = document.getElementById(`animal-select-modal-${enclosure.id}-1`);
                if (modal) (modal as any).showModal();
              }}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>

        {/* Slot 2 */}
        <div className="bg-white/10 rounded-lg p-4">
          {animal2 ? (
            <>
              <div className="text-center mb-2">
                <span className="text-4xl">{animal2.icon}</span>
                <div className="text-white font-semibold text-sm">{animal2.name}</div>
                <div className="text-slate-300 text-xs capitalize">{animal2.rarity}</div>
              </div>
              {canCollect2 && (
                <button
                  onClick={() => onCollectProduction(enclosure.id, 2)}
                  className="w-full px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                >
                  Collect {getItemIcon(animal2.produces_item_id || 0)} {animal2.produces_quantity}
                </button>
              )}
              {!canCollect2 && animal2 && (
                <div className="text-slate-400 text-xs text-center">Producing...</div>
              )}
            </>
          ) : (
            <button
              onClick={() => {
                const modal = document.getElementById(`animal-select-modal-${enclosure.id}-2`);
                if (modal) (modal as any).showModal();
              }}
              className="w-full h-full flex items-center justify-center text-slate-400 hover:text-white border-2 border-dashed border-slate-600 rounded-lg p-4 transition-colors"
            >
              + Add Animal
            </button>
          )}
        </div>
      </div>

      {/* Breeding */}
      {enclosure.breeding_started_at && (
        <div className="mb-4 bg-purple-900/50 rounded-lg p-3 text-center">
          {breedingComplete ? (
            <button
              onClick={() => onCollectBred(enclosure.id)}
              className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
            >
              Collect Bred Animal! 🎉
            </button>
          ) : (
            <div className="text-white">
              <div className="text-sm mb-1">Breeding in progress...</div>
              <div className="text-xs text-purple-300">{formatTimeLeft(enclosure.breeding_completes_at!)}</div>
            </div>
          )}
        </div>
      )}

      {canBreed && (
        <button
          onClick={() => onStartBreeding(enclosure.id)}
          className="w-full px-4 py-2 bg-purple-600 hover:bg-purple-500 text-white rounded-lg font-semibold transition-colors"
        >
          Start Breeding 💕
        </button>
      )}
    </div>
  );
};

export default function ZooPage() {
  const {
    enclosures,
    animalTypes,
    loading,
    fetchEnclosures,
    fetchAnimalTypes,
    createEnclosure,
    addAnimalToEnclosure,
    collectProduction,
    startBreeding,
    collectBredAnimal,
    subscribeToZoo
  } = useZooStore();
  const { crystals } = usePlayerStore();
  const [newEnclosureName, setNewEnclosureName] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);

  useEffect(() => {
    fetchEnclosures();
    fetchAnimalTypes();
    const unsubscribe = subscribeToZoo();
    return unsubscribe;
  }, [fetchEnclosures, fetchAnimalTypes, subscribeToZoo]);

  const handleCreateEnclosure = async () => {
    if (!newEnclosureName.trim()) {
      toast.error('Please enter an enclosure name');
      return;
    }
    try {
      await createEnclosure(newEnclosureName.trim());
      setNewEnclosureName('');
      setShowCreateModal(false);
    } catch (error) {
      // Error handled in store
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Zoo</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-900 via-emerald-900 to-teal-900 p-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-white">Zoo</h1>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 px-4 py-2 bg-slate-800/60 rounded-lg">
              <span className="text-2xl">💎</span>
              <span className="text-white font-mono">{crystals.toLocaleString()}</span>
            </div>
            <button
              onClick={() => setShowCreateModal(true)}
              className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
            >
              + New Enclosure
            </button>
          </div>
        </div>

        {/* Enclosures */}
        {enclosures.length === 0 ? (
          <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
            <p className="text-slate-300 text-lg mb-4">No enclosures yet</p>
            <p className="text-slate-400 mb-4">Create your first enclosure to start collecting animals!</p>
            <button
              onClick={() => setShowCreateModal(true)}
              className="px-6 py-3 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
            >
              Create Enclosure
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {enclosures.map((enclosure) => (
              <EnclosureCard
                key={enclosure.id}
                enclosure={enclosure}
                animalTypes={animalTypes}
                onAddAnimal={addAnimalToEnclosure}
                onCollectProduction={collectProduction}
                onStartBreeding={startBreeding}
                onCollectBred={collectBredAnimal}
              />
            ))}
          </div>
        )}

        {/* Animal Types Reference */}
        <div className="mt-8">
          <h2 className="text-2xl font-bold text-white mb-4">Available Animals</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {animalTypes.map((animal) => (
              <div
                key={animal.id}
                className={`bg-gradient-to-br ${
                  animal.rarity === 'legendary' ? 'from-purple-600 to-pink-600' :
                  animal.rarity === 'rare' ? 'from-blue-600 to-indigo-600' :
                  'from-gray-600 to-slate-600'
                } rounded-xl p-4 border border-white/20`}
              >
                <div className="text-center">
                  <div className="text-4xl mb-2">{animal.icon}</div>
                  <div className="text-white font-semibold mb-1">{animal.name}</div>
                  <div className="text-yellow-400 text-sm mb-2">💎 {animal.base_cost_crystals}</div>
                  <div className="text-white/80 text-xs capitalize mb-2">{animal.rarity}</div>
                  {animal.produces_item_id && (
                    <div className="text-white/90 text-xs">
                      Produces: {getItemIcon(animal.produces_item_id)} {getItemName(animal.produces_item_id)} every {animal.produces_interval_minutes}m
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Create Enclosure Modal */}
        {showCreateModal && (
          <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50" onClick={() => setShowCreateModal(false)}>
            <div className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl p-6 max-w-md w-full mx-4 border-2 border-slate-700" onClick={(e) => e.stopPropagation()}>
              <h3 className="text-2xl font-bold text-white mb-4">Create Enclosure</h3>
              <input
                type="text"
                value={newEnclosureName}
                onChange={(e) => setNewEnclosureName(e.target.value)}
                placeholder="Enclosure name..."
                className="w-full px-4 py-2 bg-slate-700 text-white rounded-lg mb-4"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    handleCreateEnclosure();
                  }
                }}
              />
              <div className="flex gap-2">
                <button
                  onClick={() => setShowCreateModal(false)}
                  className="flex-1 px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg font-semibold transition-colors"
                >
                  Cancel
                </button>
                <button
                  onClick={handleCreateEnclosure}
                  className="flex-1 px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold transition-colors"
                >
                  Create
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

