import { type JSX, type ReactNode, useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Easing, StyleSheet } from 'react-native';

const DURATION_MS = 220;
const SLIDE_PX = 32;

/** Follows the system "Reduce motion" setting (iOS) / "Remove animations" (Android). */
export function useReduceMotion(): boolean {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    let active = true;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((value) => active && setReduce(value))
      .catch(() => undefined);
    const subscription = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduce);
    return () => {
      active = false;
      subscription.remove();
    };
  }, []);
  return reduce;
}

/**
 * One tab's screen. It stays mounted; switching tabs cross-fades the screens
 * and slides them in the direction of travel (+1 = moving right in the tab
 * bar, -1 = left). With reduced motion it only cross-fades.
 */
export function TabScene({
  active,
  direction,
  children,
}: {
  active: boolean;
  direction: number;
  children: ReactNode;
}): JSX.Element {
  const reduceMotion = useReduceMotion();
  const opacity = useRef(new Animated.Value(active ? 1 : 0)).current;
  const shift = useRef(new Animated.Value(0)).current;
  const mounted = useRef(false);

  useEffect(() => {
    // The initial tab appears without animating.
    if (!mounted.current) {
      mounted.current = true;
      return;
    }
    const offset = reduceMotion ? 0 : SLIDE_PX * direction;
    shift.setValue(active ? offset : 0);
    const animation = Animated.parallel([
      Animated.timing(opacity, {
        toValue: active ? 1 : 0,
        duration: DURATION_MS,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
      Animated.timing(shift, {
        toValue: active ? 0 : -offset,
        duration: DURATION_MS,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }),
    ]);
    animation.start();
    return () => animation.stop();
    // Only re-run when this scene becomes active or inactive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active]);

  return (
    <Animated.View
      style={[
        StyleSheet.absoluteFill,
        { zIndex: active ? 1 : 0, opacity, transform: [{ translateX: shift }] },
      ]}
      pointerEvents={active ? 'auto' : 'none'}
      accessibilityElementsHidden={!active}
      importantForAccessibility={active ? 'auto' : 'no-hide-descendants'}
    >
      {children}
    </Animated.View>
  );
}

/** Fades its content in when it first appears, e.g. after finishing the health form. */
export function FadeIn({ children }: { children: ReactNode }): JSX.Element {
  const reduceMotion = useReduceMotion();
  const opacity = useRef(new Animated.Value(0)).current;
  const rise = useRef(new Animated.Value(12)).current;

  useEffect(() => {
    if (reduceMotion) rise.setValue(0);
    const animation = Animated.parallel([
      Animated.timing(opacity, { toValue: 1, duration: 260, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
      Animated.timing(rise, { toValue: 0, duration: 260, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
    ]);
    animation.start();
    return () => animation.stop();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Animated.View style={{ flex: 1, opacity, transform: [{ translateY: rise }] }}>{children}</Animated.View>
  );
}
