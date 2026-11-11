import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { logEventsPlugin } from './log-events-plugin';

export default {
    system: hapTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: [logEventsPlugin()]  /* Custom plugin to extend the functionality of Hvigor. */
}
