import React, { useState, useEffect } from 'react';

const API_URL = process.env.REACT_APP_API_URL || 'http://backend-service:3001';

function VisitorCounter() {
  const [visitorCount, setVisitorCount] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Function to fetch and increment visitor count
    const trackVisitor = async () => {
      try {
        const response = await fetch(`${API_URL}/api/visitors`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          setVisitorCount(data.count);
        } else {
          console.error('Failed to track visitor');
          // Fallback to just getting current count
          const getResponse = await fetch(`${API_URL}/api/visitors`);
          if (getResponse.ok) {
            const data = await getResponse.json();
            setVisitorCount(data.count);
          }
        }
      } catch (error) {
        console.error('Error tracking visitor:', error);
        // Set a default count if API is unavailable
        setVisitorCount(0);
      } finally {
        setLoading(false);
      }
    };

    trackVisitor();
  }, []);

  if (loading) {
    return (
      <div className="visitor-counter">
        <p>Loading visitor count...</p>
      </div>
    );
  }

  return (
    <div className="visitor-counter">
      <div className="counter-display">
        <span className="counter-label">Visitors: </span>
        <span className="counter-number">{visitorCount.toLocaleString()}</span>
      </div>
    </div>
  );
}

export default VisitorCounter;