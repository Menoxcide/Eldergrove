'use client';

import { useEffect, useState } from 'react';
import { useFriendsStore } from '@/stores/useFriendsStore';
import { useRouter } from 'next/navigation';
import { Skeleton } from '@/components/ui/LoadingSkeleton';
import { createClient } from '@/lib/supabase/client';

export default function FriendsPage() {
  const {
    friends,
    pendingRequests,
    loading,
    fetchFriends,
    sendFriendRequest,
    acceptFriendRequest,
    removeFriend,
    subscribeToFriends
  } = useFriendsStore();
  const router = useRouter();
  const [searchUsername, setSearchUsername] = useState('');
  const [searchResults, setSearchResults] = useState<Array<{ id: string; username: string; level: number }>>([]);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    fetchFriends();
    const unsubscribe = subscribeToFriends();
    return unsubscribe;
  }, [fetchFriends, subscribeToFriends]);

  const handleSearch = async () => {
    if (!searchUsername.trim()) return;
    setSearching(true);
    try {
      const supabase = createClient();
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, level')
        .ilike('username', `%${searchUsername.trim()}%`)
        .limit(10);
      
      if (error) throw error;
      setSearchResults(data || []);
    } catch (error: any) {
      console.error('Error searching:', error);
    } finally {
      setSearching(false);
    }
  };

  const handleSendRequest = async (friendId: string) => {
    try {
      await sendFriendRequest(friendId);
      setSearchUsername('');
      setSearchResults([]);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleAccept = async (friendId: string) => {
    try {
      await acceptFriendRequest(friendId);
    } catch (error) {
      // Error handled in store
    }
  };

  const handleRemove = async (friendId: string) => {
    if (confirm('Remove this friend?')) {
      try {
        await removeFriend(friendId);
      } catch (error) {
        // Error handled in store
      }
    }
  };

  const handleVisit = (friendId: string) => {
    router.push(`/game/friends/${friendId}`);
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4">
        <div className="max-w-6xl mx-auto">
          <h1 className="text-3xl font-bold text-white mb-6 text-center">Friends</h1>
          <div className="flex justify-center">
            <Skeleton className="w-full h-64" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-900 via-indigo-900 to-purple-900 p-4">
      <div className="max-w-6xl mx-auto">
        <h1 className="text-3xl font-bold text-white mb-6 text-center">Friends</h1>

        {/* Search for Friends */}
        <div className="mb-6 bg-white/10 backdrop-blur-md rounded-2xl p-6 border border-white/20">
          <h2 className="text-xl font-bold text-white mb-4">Search for Friends</h2>
          <div className="flex gap-2">
            <input
              type="text"
              value={searchUsername}
              onChange={(e) => setSearchUsername(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  handleSearch();
                }
              }}
              placeholder="Enter username..."
              className="flex-1 px-4 py-2 bg-slate-800 text-white rounded-lg border border-slate-700"
            />
            <button
              onClick={handleSearch}
              disabled={searching}
              className="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-semibold transition-colors disabled:opacity-50"
            >
              {searching ? 'Searching...' : 'Search'}
            </button>
          </div>

          {/* Search Results */}
          {searchResults.length > 0 && (
            <div className="mt-4 space-y-2">
              {searchResults.map((user) => (
                <div
                  key={user.id}
                  className="flex items-center justify-between p-3 bg-slate-800/60 rounded-lg"
                >
                  <div>
                    <div className="text-white font-semibold">{user.username}</div>
                    <div className="text-slate-400 text-sm">Level {user.level}</div>
                  </div>
                  <button
                    onClick={() => handleSendRequest(user.id)}
                    className="px-4 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                  >
                    Add Friend
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Pending Requests */}
        {pendingRequests.length > 0 && (
          <div className="mb-6">
            <h2 className="text-xl font-bold text-white mb-4">Pending Requests</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {pendingRequests.map((request) => (
                <div
                  key={request.id}
                  className="bg-gradient-to-br from-yellow-900 to-orange-900 rounded-xl p-4 border border-yellow-500/30"
                >
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <div className="text-white font-semibold">
                        {request.friend_profile?.username || 'Unknown'}
                      </div>
                      <div className="text-yellow-300 text-sm">Level {request.friend_profile?.level || 0}</div>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleAccept(request.friend_id)}
                      className="flex-1 px-3 py-2 bg-green-600 hover:bg-green-500 text-white rounded-lg font-semibold text-sm transition-colors"
                    >
                      Accept
                    </button>
                    <button
                      onClick={() => handleRemove(request.friend_id)}
                      className="flex-1 px-3 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold text-sm transition-colors"
                    >
                      Decline
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Friends List */}
        <div>
          <h2 className="text-xl font-bold text-white mb-4">
            Friends ({friends.length})
          </h2>
          {friends.length === 0 ? (
            <div className="bg-white/10 backdrop-blur-md rounded-2xl p-8 text-center">
              <p className="text-slate-300 text-lg">No friends yet</p>
              <p className="text-slate-400 mt-2">Search for players to add as friends!</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {friends.map((friend) => (
                <div
                  key={friend.id}
                  className="bg-gradient-to-br from-blue-900 to-indigo-900 rounded-xl p-4 border border-blue-500/30"
                >
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <div className="text-white font-semibold">
                        {friend.friend_profile?.username || 'Unknown'}
                      </div>
                      <div className="text-blue-300 text-sm">Level {friend.friend_profile?.level || 0}</div>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    <button
                      onClick={() => handleVisit(friend.friend_id)}
                      className="flex-1 px-3 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-semibold text-sm transition-colors"
                    >
                      Visit Town
                    </button>
                    <button
                      onClick={() => handleRemove(friend.friend_id)}
                      className="px-3 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg font-semibold text-sm transition-colors"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

