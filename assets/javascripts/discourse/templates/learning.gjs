import LearningDashboard from "../components/learning-dashboard";

const LearningTemplate = <template>
  <LearningDashboard @model={{@controller.model}} />
</template>;
export default LearningTemplate;
