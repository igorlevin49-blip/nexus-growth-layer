import { useEffect } from "react";
import { useIsMutating } from "@tanstack/react-query";
import { useLoader } from "@/contexts/LoaderContext";

/**
 * Hook to automatically show/hide global loader based on React Query state
 * Shows loader ONLY for mutations (create, update, delete)
 * Data fetching uses local Skeleton components for better UX
 */
export function useGlobalLoader() {
  const isMutating = useIsMutating();
  const { showLoader, hideLoader } = useLoader();

  useEffect(() => {
    // Show loader ONLY for mutations (create, update, delete)
    // NOT for data fetching - pages handle that with Skeletons
    if (isMutating > 0) {
      showLoader();
    } else {
      hideLoader();
    }
  }, [isMutating, showLoader, hideLoader]);
}
